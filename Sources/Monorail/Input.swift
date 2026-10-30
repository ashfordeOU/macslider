#if os(macOS)
import AppKit
import MonorailCore

extension Modifiers {
    init(_ flags: CGEventFlags) {
        var mods: Modifiers = []
        if flags.contains(.maskControl) { mods.insert(.control) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskCommand) { mods.insert(.command) }
        self = mods
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var mods: Modifiers = []
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        self = mods
    }
}

/// Global keyboard shortcuts, slide mode and strip scrolling, through a
/// `CGEventTap`. Matching events are consumed; everything else passes through.
final class InputMonitor {
    var keymap: Keymap = .default
    /// While true (e.g. while recording a shortcut) every event passes through.
    var isSuspended = false
    /// When paused only the pause shortcut is handled.
    var isPaused: () -> Bool = { false }
    /// Scroll the strip while holding `scrollModifier`.
    var modifierSwipe = true
    var scrollModifier: Modifiers = [.option]
    /// Scroll the strip when the pointer is over the menu bar, without keys.
    var scrollOverMenuBar = true
    /// True if a point (Accessibility coordinates) is on a menu bar.
    var isOverMenuBar: (CGPoint) -> Bool = { _ in false }
    var slideTrigger: SlideTrigger = .rightOption {
        didSet { if slideTrigger == .off { setSlideMode(false) } }
    }

    var onAction: (Action) -> Void = { _ in }
    /// Free scrolling by a number of points (trackpads, Magic Mouse).
    var onScroll: (Double) -> Void = { _ in }
    var onScrollEnd: () -> Void = {}
    /// One notch of a mouse wheel: true for the next column, false for the previous.
    var onStep: (Bool) -> Void = { _ in }
    var onSlideModeChange: (Bool) -> Void = { _ in }

    private(set) var isSlideMode = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var scrollEndTimer: Timer?
    private var slideIdleTimer: Timer?
    private var triggerDownAt: CFTimeInterval?
    private var triggerInterrupted = false
    private var lastStep: CFTimeInterval = 0

    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Installs the event tap. Fails without Accessibility permission.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            log.error("Could not create the event tap")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        setSlideMode(false)
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    // MARK: Slide mode

    func setSlideMode(_ on: Bool) {
        slideIdleTimer?.invalidate()
        slideIdleTimer = nil
        if on { restartSlideIdleTimer() }
        guard on != isSlideMode else { return }
        isSlideMode = on
        onSlideModeChange(on)
    }

    private func restartSlideIdleTimer() {
        slideIdleTimer?.invalidate()
        slideIdleTimer = Timer.scheduledTimer(withTimeInterval: SlideMode.idleTimeout, repeats: false) {
            [weak self] _ in self?.setSlideMode(false)
        }
    }

    /// A tap of the trigger key on its own (pressed and released quickly,
    /// with nothing else pressed in between) toggles slide mode.
    private func handleFlagsChanged(_ event: CGEvent) {
        guard !isSuspended, let triggerCode = slideTrigger.keyCode else { return }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == triggerCode else {
            if triggerDownAt != nil { triggerInterrupted = true }
            return
        }
        let now = CACurrentMediaTime()
        if event.flags.rawValue & slideTrigger.deviceFlag != 0 {
            triggerDownAt = now
            triggerInterrupted = false
        } else if let start = triggerDownAt {
            triggerDownAt = nil
            if !triggerInterrupted && now - start <= SlideMode.maximumTapDuration && !isPaused() {
                setSlideMode(!isSlideMode)
            }
        }
    }

    // MARK: Events

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .flagsChanged:
            handleFlagsChanged(event)
            return pass
        case .keyDown:
            if triggerDownAt != nil { triggerInterrupted = true }
            guard !isSuspended else { return pass }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = Modifiers(event.flags)
            if isSlideMode {
                switch SlideMode.resolve(keyCode: keyCode, modifiers: modifiers) {
                case .action(let action):
                    restartSlideIdleTimer()
                    DispatchQueue.main.async { self.onAction(action) }
                    return nil
                case .exit:
                    setSlideMode(false)
                    return nil
                case .passThrough:
                    setSlideMode(false)
                }
            }
            guard let action = keymap.action(for: Shortcut(keyCode: keyCode, modifiers: modifiers)) else {
                return pass
            }
            if isPaused() && action != .togglePause { return pass }
            DispatchQueue.main.async { self.onAction(action) }
            return nil
        case .scrollWheel:
            if triggerDownAt != nil { triggerInterrupted = true }
            return handleScroll(event) ? nil : pass
        default:
            return pass
        }
    }

    /// Returns true if the scroll moved the strip (and should not reach the app).
    private func handleScroll(_ event: CGEvent) -> Bool {
        guard !isSuspended, !isPaused() else { return false }
        var mods = Modifiers(event.flags)
        mods.remove(.shift)  // Shift turns a mouse wheel sideways; allow it.
        let withModifier = modifierSwipe && !scrollModifier.isEmpty && mods == scrollModifier
        let overMenuBar = scrollOverMenuBar && mods.isEmpty && isOverMenuBar(event.location)
        guard withModifier || overMenuBar || isSlideMode else { return false }
        if isSlideMode { restartSlideIdleTimer() }

        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            // Trackpad or Magic Mouse: follow the fingers point for point.
            let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let delta = abs(dx) >= abs(dy) ? -dx : -dy
            guard delta != 0 else { return true }
            onScroll(delta)
            scrollEndTimer?.invalidate()
            scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                self?.onScrollEnd()
            }
        } else {
            // Mouse wheel: one notch moves one column.
            let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let value = abs(dx) >= abs(dy) ? dx : dy
            let now = CACurrentMediaTime()
            guard value != 0, now - lastStep > 0.07 else { return true }
            lastStep = now
            onStep(value < 0)
        }
        return true
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

// MARK: - Three- and four-finger swipes

/// One contact as reported by the private MultitouchSupport framework.
private struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTVector
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTVector
    var zero2: (Int32, Int32)
    var density: Float
}

private typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

/// Reads raw finger positions from built-in and Magic trackpads so a plain
/// three- or four-finger swipe can scroll the strip. The framework is loaded
/// at runtime; if it is unavailable the feature quietly does nothing.
final class TrackpadSwipe {
    static let shared = TrackpadSwipe()

    var fingers = 0
    /// Horizontal movement as a fraction of the trackpad width.
    var onScroll: (Double) -> Void = { _ in }
    var onEnd: () -> Void = {}

    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private let handle = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
    private var devices: [UnsafeMutableRawPointer] = []
    private var deviceList: CFArray?

    // Gesture state, touched only on the callback thread.
    private var lastX: Float?
    private var startX: Float = 0
    private var startY: Float = 0
    private var isSwiping = false

    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    func start() {
        guard devices.isEmpty,
            let createList = symbol("MTDeviceCreateList", as: CreateListFn.self),
            let register = symbol("MTRegisterContactFrameCallback", as: RegisterFn.self),
            let startDevice = symbol("MTDeviceStart", as: StartFn.self),
            let list = createList()?.takeRetainedValue()
        else { return }
        deviceList = list
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            register(device, multitouchCallback)
            startDevice(device, 0)
            devices.append(device)
        }
    }

    func stop() {
        if let stopDevice = symbol("MTDeviceStop", as: StopFn.self) {
            devices.forEach { stopDevice($0) }
        }
        devices.removeAll()
        deviceList = nil
    }

    fileprivate func frame(_ touches: UnsafeMutableRawPointer?, count: Int32) {
        let wanted = fingers
        guard wanted > 0 else { return }
        guard Int(count) == wanted, let touches else {
            if isSwiping {
                isSwiping = false
                DispatchQueue.main.async { self.onEnd() }
            }
            lastX = nil
            return
        }
        let contacts = touches.bindMemory(to: MTTouch.self, capacity: Int(count))
        var sumX: Float = 0
        var sumY: Float = 0
        for i in 0..<Int(count) {
            sumX += contacts[i].normalized.position.x
            sumY += contacts[i].normalized.position.y
        }
        let x = sumX / Float(count)
        let y = sumY / Float(count)
        guard let previous = lastX else {
            lastX = x
            startX = x
            startY = y
            return
        }
        lastX = x
        if !isSwiping {
            // Only claim clearly horizontal movement, so vertical swipes stay with macOS.
            let dx = abs(x - startX)
            let dy = abs(y - startY)
            guard dx > 0.03, dx > dy * 1.5 else { return }
            isSwiping = true
        }
        let delta = Double(x - previous)
        DispatchQueue.main.async { self.onScroll(delta) }
    }
}

private func multitouchCallback(
    _ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?, _ count: Int32,
    _ timestamp: Double, _ frame: Int32
) -> Int32 {
    TrackpadSwipe.shared.frame(touches, count: count)
    return 0
}
#endif
