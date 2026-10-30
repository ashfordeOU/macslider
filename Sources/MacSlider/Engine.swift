#if os(macOS)
import AppKit
import MacSliderCore
import os

let log = Logger(subsystem: "org.ashforde.macslider", category: "engine")

/// One display on one Mission Control Space.
struct ScreenKey: Hashable, Codable {
    var display: String
    var space: UInt64
}

/// A strip lives on one display, one Mission Control Space and one
/// MacSlider workspace (0-based).
struct StripKey: Hashable, Codable {
    var display: String
    var space: UInt64
    var workspace: Int

    init(screen: ScreenKey, workspace: Int) {
        display = screen.display
        space = screen.space
        self.workspace = workspace
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        display = try c.decode(String.self, forKey: .display)
        space = try c.decode(UInt64.self, forKey: .space)
        workspace = try c.decodeIfPresent(Int.self, forKey: .workspace) ?? 0
    }

    var screen: ScreenKey { ScreenKey(display: display, space: space) }
}

/// A window MacSlider knows about: tiled on a strip (`key` set) or floating.
final class ManagedWindow {
    let id: WindowID
    let pid: pid_t
    let element: AXUIElement
    let bundleID: String?
    let appName: String
    /// The frame the window had before MacSlider first touched it.
    let home: CGRect
    /// The last frame MacSlider applied, to skip redundant moves and to tell
    /// the user's own moves apart from ours.
    var lastApplied: Rect?
    /// The strip the window is tiled on, or nil when it floats.
    var key: StripKey?

    init(id: WindowID, pid: pid_t, element: AXUIElement, bundleID: String?, appName: String, home: CGRect) {
        self.id = id
        self.pid = pid
        self.element = element
        self.bundleID = bundleID
        self.appName = appName
        self.home = home
    }

    var title: String { element.title ?? "" }
}

/// Owns the strips and keeps real windows in line with them.
///
/// Everything runs on the main thread. Accessibility calls are bounded by a
/// global messaging timeout so an unresponsive app cannot stall the engine
/// for long.
final class Engine {
    var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    private(set) var isPaused = false
    private(set) var isRunning = false

    /// Called whenever something the menu bar shows may have changed.
    var onStateChange: () -> Void = {}
    /// Called for the "Search windows" action.
    var onShowSwitcher: () -> Void = {}
    /// Called for the "Overview" action.
    var onShowOverview: () -> Void = {}

    private var windows: [WindowID: ManagedWindow] = [:]
    private var strips: [StripKey: Strip] = [:]
    /// The workspace shown on each display and Space.
    private var activeWorkspace: [ScreenKey: Int] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var displays: [Display] = []
    private let animator = Animator()
    private let overlays = Overlays()
    private var lastApplyTime: CFTimeInterval = 0
    private var enhancedUIRestore: Set<pid_t> = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var mouseUpTimer: Timer?
    private var saveTimer: Timer?
    private var syncTimer: Timer?
    private var swipeDisplay: Display?
    private var lastFocusFollowsMouse: CFTimeInterval = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(settings: AppSettings) {
        self.settings = settings
        animator.apply = { [weak self] id, rect, sizeChanged in
            self?.apply(rect, to: id, sizeChanged: sizeChanged)
        }
        animator.onFinish = { [weak self] in
            self?.restoreEnhancedUI()
            self?.updateOverlays()
        }
        overlays.onSelectWindow = { [weak self] id in self?.focusAndReveal(id) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        loadState()
        registerWorkspaceNotifications()
        sync()
        log.info("Engine started with \(self.windows.count) windows")
    }

    /// Puts every window back on screen and saves the layout. Called on quit.
    func shutdown() {
        guard isRunning else { return }
        animator.finishNow()
        saveState()
        restoreAll()
        overlays.hideAll()
    }

    func togglePause() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            animator.finishNow()
            restoreAll()
            overlays.hideAll()
        } else {
            for window in windows.values { window.lastApplied = nil }
            sync()
        }
        onStateChange()
    }

    /// Forgets cached frames and re-applies the layout from scratch.
    func retile() {
        guard !isPaused else { return }
        for window in windows.values { window.lastApplied = nil }
        sync()
    }

    private func settingsDidChange(from old: AppSettings) {
        guard isRunning, !isPaused else { return }
        if settings.layout != old.layout || settings.keepHeights != old.keepHeights
            || settings.sliderBar != old.sliderBar || settings.sliderBarEdge != old.sliderBarEdge
        {
            for (key, var strip) in strips {
                if let display = display(for: key) {
                    strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
                }
                strips[key] = strip
            }
            layout(animated: true)
        } else {
            updateOverlays()
        }
        onStateChange()
    }

    // MARK: - Actions

    func perform(_ requested: Action) {
        let action = visual(requested)
        switch action {
        case .togglePause:
            togglePause()
            return
        case .retile:
            retile()
            return
        case .windowSwitcher:
            onShowSwitcher()
            return
        case .overview:
            onShowOverview()
            return
        default:
            break
        }
        guard isRunning, !isPaused else { return }
        if let n = action.workspaceNumber {
            switchWorkspace(to: n - 1)
            return
        }
        if let n = action.moveToWorkspaceNumber {
            moveFocusedWindow(toWorkspace: n - 1)
            return
        }
        animator.finishNow()

        switch action {
        case .toggleFloat:
            toggleFloat()
            return
        case .sendToNextDisplay:
            sendToNextDisplay()
            return
        case .toggleNativeFullScreen:
            if let id = focusedWindowID(), let window = windows[id] ?? adoptFocused(id) {
                window.element.set("AXFullScreen", (window.element.isFullScreen ? kCFBooleanFalse : kCFBooleanTrue)!)
            }
            return
        default:
            break
        }

        guard let (display, key) = activeContext(), var strip = strips[key], !strip.isEmpty else { return }
        let config = settings.layout
        let width = viewport(of: display).width
        if let focused = focusedWindowID(), strip.contains(focused) { strip.focus(focused) }

        var reveal = true
        switch action {
        case .focusLeft: strip.moveFocus(.left)
        case .focusRight: strip.moveFocus(.right)
        case .focusUp: strip.moveFocus(.up)
        case .focusDown: strip.moveFocus(.down)
        case .focusFirst: strip.focusColumn(at: 0)
        case .focusLast: strip.focusColumn(at: strip.columns.count - 1)
        case .moveLeft: strip.moveFocused(.left)
        case .moveRight: strip.moveFocused(.right)
        case .moveUp: strip.moveFocused(.up)
        case .moveDown: strip.moveFocused(.down)
        case .cycleWidth: strip.cycleWidth(presets: config.sanitizedPresets, forward: true)
        case .cycleWidthBackward: strip.cycleWidth(presets: config.sanitizedPresets, forward: false)
        case .narrower: strip.adjustWidth(by: -0.1)
        case .wider: strip.adjustWidth(by: 0.1)
        case .toggleFullWidth: strip.toggleFullWidth()
        case .center:
            strip.centerFocused(config: config, viewportWidth: width)
            reveal = false
        case .consumeIntoLeft: strip.consumeIntoLeft()
        case .consumeIntoRight: strip.consumeIntoRight()
        case .expelLeft: strip.expelLeft()
        case .expel: strip.expel()
        case .cycleLayout: strip.cycleArrangement()
        case .mainLarger: strip.adjustSplit(by: 0.05)
        case .mainSmaller: strip.adjustSplit(by: -0.05)
        case .makeMain: strip.promoteToMain()
        case .regroup:
            let groups = Grouping.plan(
                strip.columns.filter { $0.pin == nil }.flatMap(\.windows),
                app: { [weak self] id in self?.windows[id].map(Self.appKey) ?? "" },
                capacity: { [weak self] app in self?.settings.tiles(for: app) ?? 2 },
                pairSize: settings.tilesPerSlide
            )
            strip.regroup(groups, width: 1) { [weak self] group in
                guard let self, let first = group.first else { return .grid }
                return self.settings.arrangement(for: self.windows[first]?.bundleID)
            }
        case .pinLeft: strip.togglePin(.left)
        case .pinRight: strip.togglePin(.right)
        case .toggleTabbed: strip.toggleTabbed()
        default:
            if let number = action.columnNumber { strip.focusColumn(at: number - 1) }
        }
        if reveal { strip.revealFocused(config: config, viewportWidth: width) }
        strips[key] = strip
        layout(animated: true)
        if let target = strip.focusedWindow, target != focusedWindowID() {
            focus(target, warpMouse: true)
        }
        scheduleSave()
    }

    /// Keys name what you see: with a right-to-left strip, "left" is the
    /// strip's next column, so left and right actions swap.
    private func visual(_ action: Action) -> Action {
        guard settings.layout.direction == .rightToLeft else { return action }
        let swaps: [Action: Action] = [
            .focusLeft: .focusRight, .focusRight: .focusLeft,
            .moveLeft: .moveRight, .moveRight: .moveLeft,
            .consumeIntoLeft: .consumeIntoRight, .consumeIntoRight: .consumeIntoLeft,
            .expelLeft: .expel, .expel: .expelLeft,
            .pinLeft: .pinRight, .pinRight: .pinLeft,
        ]
        return swaps[action] ?? action
    }

    /// Focuses any managed window, scrolling its strip to show it.
    func focusAndReveal(_ id: WindowID) {
        guard let window = windows[id] else { return }
        if let key = window.key { showWorkspace(of: key) }
        if let key = window.key, var strip = strips[key], let display = display(for: key) {
            strip.focus(id)
            strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
            strips[key] = strip
            layout(animated: true)
        }
        focus(id, warpMouse: true)
    }

    private func toggleFloat() {
        guard let id = focusedWindowID() else { return }
        guard let window = windows[id] else {
            // An unmanaged (e.g. ignored) window: tile it.
            if let window = adoptFocused(id), window.key == nil { tile(window) }
            return
        }
        if let key = window.key {
            let display = self.display(for: key)
            removeFromStrip(window)
            if let display {
                let visible = display.visibleFrame
                let size = CGSize(
                    width: min(window.home.width, visible.width * 0.8),
                    height: min(window.home.height, visible.height * 0.8))
                let frame = CGRect(
                    x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                    width: size.width, height: size.height)
                window.element.setFrame(frame)
            }
            window.lastApplied = nil
            layout(animated: true)
        } else {
            tile(window)
        }
        focus(id, warpMouse: false)
    }

    private func tile(_ window: ManagedWindow) {
        guard let frame = window.element.frame, let display = display(containing: frame) ?? displays.first else {
            return
        }
        place(window, in: currentKey(display), display: display, focus: true, restoring: false)
        layout(animated: true)
    }

    /// Adds a window to a strip: grouped into a slide by app when grouping is
    /// on, otherwise as a column of its own.
    private func place(
        _ window: ManagedWindow, in key: StripKey, display: Display, focus: Bool, width: Double? = nil,
        restoring: Bool = true
    ) {
        // A window coming back (unhidden, unminimised, reopened from the Dock,
        // or its app relaunched) returns to exactly where it was.
        if restoring, let memory = memory(for: window), memory.key.screen == key.screen {
            var strip = strips[memory.key] ?? Strip()
            let visible = memory.key == key
            strip.restore(window.id, to: memory.slot, focus: focus && visible)
            if focus && visible {
                strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
            }
            strips[memory.key] = strip
            window.key = memory.key
            scheduleSave()
            return
        }
        var strip = strips[key] ?? Strip()
        let rule = settings.rule(for: window.bundleID)
        let position = rule?.position ?? settings.newWindowPosition
        if settings.groupByApp {
            let decision = Grouping.decide(
                newApp: Self.appKey(window),
                strip: strip,
                app: { [weak self] id in self?.windows[id].map(Self.appKey) },
                capacity: { [weak self] app in self?.settings.tiles(for: app) ?? 2 },
                pairSize: settings.tilesPerSlide,
                pairLoneWindows: settings.pairLoneWindowsOnOpen
            )
            switch decision {
            case .join(let column):
                strip.add(window.id, toColumn: column, focus: focus)
            case .pairWith(let other):
                strip.remove(other)
                strip.insertSlide(
                    [other, window.id], width: 1, arrangement: settings.arrangement(for: window.bundleID),
                    position: .afterFocused, focus: focus)
            case .newSlide:
                strip.insertSlide(
                    [window.id], width: 1, arrangement: settings.arrangement(for: window.bundleID),
                    position: position, focus: focus)
            }
        } else {
            strip.insert(
                window.id, width: width ?? rule?.width ?? settings.layout.defaultWidth,
                position: position, focus: focus)
        }
        if focus { strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width) }
        strips[key] = strip
        window.key = key
        scheduleSave()
    }

    /// Windows are grouped by app bundle, or by name for apps without one.
    static func appKey(_ window: ManagedWindow) -> String {
        window.bundleID ?? window.appName
    }

    // MARK: - Workspaces

    /// Shows workspace `index` on the active display.
    func switchWorkspace(to index: Int) {
        guard index >= 0, index < settings.workspaceCount, let (display, key) = activeContext(),
            index != key.workspace
        else { return }
        activeWorkspace[key.screen] = index
        let newKey = currentKey(display)
        if var strip = strips[newKey] {
            strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
            strips[newKey] = strip
        }
        layout(animated: true)
        if let target = strips[newKey]?.focusedWindow { focus(target, warpMouse: false) }
        scheduleSave()
        onStateChange()
    }

    /// Makes the workspace that holds `key` the visible one on its display.
    private func showWorkspace(of key: StripKey) {
        guard (activeWorkspace[key.screen] ?? 0) != key.workspace else { return }
        activeWorkspace[key.screen] = key.workspace
        onStateChange()
    }

    private func moveFocusedWindow(toWorkspace index: Int) {
        guard index >= 0, index < settings.workspaceCount, let id = focusedWindowID(), let window = windows[id],
            let key = window.key, key.workspace != index, let display = display(for: key)
        else { return }
        let width = strips[key].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } }
        removeFromStrip(window)
        var target = key
        target.workspace = index
        place(window, in: target, display: display, focus: true, width: width, restoring: false)
        layout(animated: true)
        if let next = strips[key]?.focusedWindow { focus(next, warpMouse: false) }
        onStateChange()
    }

    // MARK: - Overview

    struct OverviewColumn: Identifiable {
        var id: Int
        var windows: [WindowSummary]
        var width: Double
        var arrangement: Arrangement
        var split: Double
        var isTabbed: Bool
        var isFocused: Bool
        var pin: PinSide?
    }

    struct OverviewStrip: Identifiable {
        var id: StripKey { key }
        var key: StripKey
        var title: String
        var isActive: Bool
        var columns: [OverviewColumn]
        var aspectRatio: Double
        var isRightToLeft: Bool
    }

    /// Every workspace on the displays' current Spaces, for the overview.
    func overview() -> [OverviewStrip] {
        let focused = focusedWindowID()
        var result: [OverviewStrip] = []
        for display in displays {
            let current = currentKey(display)
            for workspace in 0..<settings.workspaceCount {
                let key = StripKey(screen: current.screen, workspace: workspace)
                let strip = strips[key] ?? Strip()
                let columns = strip.columns.enumerated().map { index, column in
                    OverviewColumn(
                        id: index,
                        windows: column.windows.compactMap { id in
                            windows[id].map { summary($0, focused: id == focused) }
                        },
                        width: column.effectiveWidth,
                        arrangement: column.arrangement,
                        split: column.split,
                        isTabbed: column.isTabbed,
                        isFocused: index == strip.focusedColumn && key == current,
                        pin: column.pin
                    )
                }
                var title = settings.workspaceCount > 1 ? "Workspace \(workspace + 1)" : "Windows"
                if displays.count > 1 { title = "\(display.name) · \(title)" }
                result.append(
                    OverviewStrip(
                        key: key, title: title, isActive: key == current, columns: columns,
                        aspectRatio: display.visibleFrame.width / max(display.visibleFrame.height, 1),
                        isRightToLeft: settings.layout.direction == .rightToLeft))
            }
        }
        return result
    }

    /// Drag and drop in the overview: moves `id` into column `column` of the
    /// strip `target`, or into a new column at `newColumnAt`.
    func overviewMove(_ id: WindowID, to target: StripKey, column: Int? = nil, newColumnAt: Int? = nil) {
        guard let window = windows[id], let source = window.key else { return }
        let width = strips[source].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } }
            ?? settings.layout.defaultWidth
        if source == target {
            guard var strip = strips[target] else { return }
            if let column {
                strip.moveWindow(id, intoColumn: column)
            } else if let newColumnAt {
                strip.moveWindow(id, toNewColumnAt: newColumnAt, width: width)
            }
            strips[target] = strip
        } else {
            // Work out the target position before removing, in case both strips are the same list.
            removeFromStrip(window)
            var strip = strips[target] ?? Strip()
            if let column, strip.columns.indices.contains(column) {
                strip.add(id, toColumn: column, focus: true)
            } else {
                strip.insert(id, width: width, position: .end, focus: true)
                if let newColumnAt { strip.moveColumn(from: strip.columns.count - 1, to: newColumnAt) }
            }
            strips[target] = strip
            window.key = target
        }
        layout(animated: true)
        scheduleSave()
        onStateChange()
    }

    /// Reorders whole columns in the overview.
    func overviewMoveColumn(from: Int, to: Int, in key: StripKey) {
        guard var strip = strips[key] else { return }
        strip.moveColumn(from: from, to: to > from ? to - 1 : to)
        strips[key] = strip
        layout(animated: true)
        scheduleSave()
    }

    // MARK: - Slider bar

    struct MiniWindow: Equatable, Identifiable {
        var id: WindowID
        var pid: pid_t
        var appName: String
        var title: String
    }

    struct MiniTile: Equatable, Identifiable {
        var id: Int
        /// Position and width in strip points.
        var x: Double
        var width: Double
        var windows: [MiniWindow]
        var arrangement: Arrangement
        var split: Double
        var isFocused: Bool
    }

    /// Everything the slider bar draws for one display.
    struct MiniMap: Equatable {
        var displayUUID: String
        /// The display's visible frame, in Cocoa coordinates (for placing the bar).
        var screenFrame: CGRect
        var workspace: Int
        var workspaceCount: Int
        var tiles: [MiniTile]
        var totalWidth: Double
        /// The part of the strip on screen, in strip points.
        var viewportX: Double
        var viewportWidth: Double
        var isRightToLeft: Bool
    }

    func miniMaps() -> [MiniMap] {
        guard isRunning, !isPaused else { return [] }
        let focused = focusedWindowID()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return displays.map { display in
            let key = currentKey(display)
            let strip = strips[key] ?? Strip()
            let width = viewport(of: display).width
            let offsets = strip.columnOffsets(config: settings.layout, viewportWidth: width)
            let tiles = strip.columns.indices.filter { strip.columns[$0].pin == nil }.map { index in
                let column = strip.columns[index]
                return MiniTile(
                    id: index,
                    x: offsets[index],
                    width: strip.width(ofColumn: index, config: settings.layout, viewportWidth: width),
                    windows: column.windows.compactMap { id in
                        windows[id].map {
                            MiniWindow(id: id, pid: $0.pid, appName: $0.appName, title: $0.title)
                        }
                    },
                    arrangement: column.arrangement,
                    split: column.split,
                    isFocused: index == strip.focusedColumn && column.windows.contains { $0 == focused }
                )
            }
            let visible = display.visibleFrame
            return MiniMap(
                displayUUID: display.uuid,
                screenFrame: CGRect(
                    x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height),
                workspace: key.workspace,
                workspaceCount: settings.workspaceCount,
                tiles: tiles,
                totalWidth: strip.totalWidth(config: settings.layout, viewportWidth: width),
                viewportX: strip.scroll,
                viewportWidth: strip.scrollArea(config: settings.layout, viewportWidth: width).width,
                isRightToLeft: settings.layout.direction == .rightToLeft
            )
        }
    }

    /// Drags the strip on `displayUUID` so its viewport starts at `stripX`.
    func slide(to stripX: Double, displayUUID: String) {
        guard isRunning, !isPaused, let display = displays.first(where: { $0.uuid == displayUUID }) else { return }
        let key = currentKey(display)
        guard var strip = strips[key], !strip.isEmpty else { return }
        swipeDisplay = display
        animator.cancel()
        overlays.hideTransient()
        let width = viewport(of: display).width
        strip.scroll(by: stripX - strip.scroll, config: settings.layout, viewportWidth: width)
        strips[key] = strip
        layout(animated: false, updateOverlays: false)
    }

    /// Ends a slider-bar drag the same way a swipe ends.
    func endSlide() {
        endSwipe()
    }

    /// Shows a workspace from the overview without focusing a particular window.
    func overviewShow(_ key: StripKey) {
        showWorkspace(of: key)
        layout(animated: true)
        if let target = strips[key]?.focusedWindow { focus(target, warpMouse: false) }
    }

    private func sendToNextDisplay() {
        guard displays.count > 1, let id = focusedWindowID(), let window = windows[id], let key = window.key,
            let index = displays.firstIndex(where: { $0.uuid == key.display })
        else { return }
        let width = strips[key].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } }
        removeFromStrip(window)
        let next = displays[(index + 1) % displays.count]
        place(window, in: currentKey(next), display: next, focus: true, width: width, restoring: false)
        window.lastApplied = nil
        layout(animated: false)
        focus(id, warpMouse: true)
        scheduleSave()
    }

    // MARK: - Trackpad scrolling

    /// Scrolls the strip under the mouse pointer by `delta` points.
    func swipe(by delta: Double) {
        guard isRunning, !isPaused else { return }
        let display = swipeDisplay ?? displayUnderMouse()
        guard let display else { return }
        swipeDisplay = display
        let key = currentKey(display)
        guard var strip = strips[key], !strip.isEmpty else { return }
        let mirrored = settings.layout.direction == .rightToLeft
        let factor = settings.swipeSensitivity * (settings.invertSwipe != mirrored ? -1 : 1)
        animator.cancel()
        overlays.hideTransient()
        strip.scroll(by: delta * factor, config: settings.layout, viewportWidth: viewport(of: display).width)
        strips[key] = strip
        layout(animated: false, updateOverlays: false)
    }

    /// Ends a swipe: settles on a column edge and focuses the centred column.
    func endSwipe() {
        guard let display = swipeDisplay else { return }
        swipeDisplay = nil
        let key = currentKey(display)
        guard var strip = strips[key], !strip.isEmpty else { return }
        strip.settle(config: settings.layout, viewportWidth: viewport(of: display).width)
        strips[key] = strip
        layout(animated: true)
        if let target = strip.focusedWindow, target != focusedWindowID() {
            focus(target, warpMouse: false)
        }
        scheduleSave()
    }

    /// Moves one column left or right on the display under the mouse pointer
    /// (a mouse-wheel notch or a click on the menu bar arrows).
    /// `visual` steps (the ‹ › buttons) go to the window on that side of the
    /// screen; others (the mouse wheel) go to the strip's next window.
    func step(forward: Bool, honourReverse: Bool = true, visual: Bool = false) {
        guard isRunning, !isPaused else { return }
        var next = honourReverse && settings.invertSwipe ? !forward : forward
        if visual && settings.layout.direction == .rightToLeft { next.toggle() }
        guard let display = displayUnderMouse() ?? displays.first else { return }
        let key = currentKey(display)
        guard var strip = strips[key], !strip.isEmpty else { return }
        if let focused = focusedWindowID(), strip.contains(focused) { strip.focus(focused) }
        strip.moveFocus(next ? .right : .left)
        strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
        strips[key] = strip
        layout(animated: true)
        if let target = strip.focusedWindow, target != focusedWindowID() {
            focus(target, warpMouse: false)
        }
        scheduleSave()
    }

    // MARK: - Focus follows mouse

    func mouseMoved(to point: CGPoint) {
        guard settings.focusFollowsMouse, isRunning, !isPaused, swipeDisplay == nil,
            NSEvent.pressedMouseButtons == 0
        else { return }
        let now = CACurrentMediaTime()
        guard now - lastFocusFollowsMouse > 0.15 else { return }
        lastFocusFollowsMouse = now
        guard let id = topWindow(at: point), let window = windows[id], window.key != nil,
            id != focusedWindowID()
        else { return }
        focus(id, warpMouse: false)
    }

    /// The front-most normal window under `point` (Accessibility coordinates).
    private func topWindow(at point: CGPoint) -> WindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                bounds.contains(point),
                let number = entry[kCGWindowNumber as String] as? NSNumber
            else { continue }
            if (entry[kCGWindowOwnerPID as String] as? pid_t) == ownPID { continue }
            return WindowID(number.uint32Value)
        }
        return nil
    }

    // MARK: - Queries for the UI

    struct Status {
        var workspace: Int
        var focusedColumn: Int
        var columnCount: Int
    }

    func status() -> Status? {
        guard isRunning, let (_, key) = activeContext() else { return nil }
        let strip = strips[key] ?? Strip()
        return Status(
            workspace: key.workspace + 1,
            focusedColumn: strip.isEmpty ? 0 : strip.focusedColumn + 1,
            columnCount: strip.columns.count)
    }

    struct WindowSummary: Identifiable {
        var id: WindowID
        var appName: String
        var title: String
        var isTiled: Bool
        var isFocused: Bool
        var icon: NSImage?
    }

    /// Windows of the active strip, left to right.
    func activeStripWindows() -> [WindowSummary] {
        guard let (_, key) = activeContext(), let strip = strips[key] else { return [] }
        let focused = strip.focusedWindow
        return strip.allWindows.compactMap { id in
            windows[id].map { summary($0, focused: id == focused) }
        }
    }

    /// Every managed window on the current Spaces, tiled ones first.
    func allWindowSummaries() -> [WindowSummary] {
        let focused = focusedWindowID()
        var result: [WindowSummary] = []
        for display in displays {
            guard let strip = strips[currentKey(display)] else { continue }
            for id in strip.allWindows {
                if let window = windows[id] { result.append(summary(window, focused: id == focused)) }
            }
        }
        for window in windows.values where window.key == nil {
            result.append(summary(window, focused: window.id == focused))
        }
        return result
    }

    private func summary(_ window: ManagedWindow, focused: Bool) -> WindowSummary {
        WindowSummary(
            id: window.id,
            appName: window.appName,
            title: window.title,
            isTiled: window.key != nil,
            isFocused: focused,
            icon: NSRunningApplication(processIdentifier: window.pid)?.icon
        )
    }

    // MARK: - Layout

    private func layout(animated: Bool, updateOverlays shouldUpdateOverlays: Bool = true) {
        guard isRunning, !isPaused else { return }
        var targets: [WindowID: (from: Rect, to: Rect)] = [:]
        for display in displays {
            let key = currentKey(display)
            let strip = strips[key] ?? Strip()
            for placement in strip.layout(config: settings.layout, viewport: viewport(of: display)) {
                guard let window = windows[placement.window] else { continue }
                var frame = placement.frame
                if settings.keepHeights, let (c, _) = strip.locate(placement.window),
                    strip.columns[c].windows.count == 1, !strip.columns[c].isTabbed
                {
                    frame.height = min(frame.height, window.home.height.rounded())
                }
                let from = window.lastApplied ?? window.element.frame.map(Rect.init) ?? frame
                targets[placement.window] = (from, frame)
            }
            // Windows of the other workspaces wait in the bottom-right corner,
            // a point from fully hidden (macOS won't move them all the way off).
            for (otherKey, other) in strips where otherKey.screen == key.screen && otherKey != key {
                for id in other.allWindows {
                    guard let window = windows[id] else { continue }
                    let current = window.lastApplied ?? window.element.frame.map(Rect.init)
                    guard let current else { continue }
                    let hidden = Rect(
                        x: display.frame.maxX - 1, y: display.frame.maxY - 1,
                        width: current.width, height: current.height)
                    targets[id] = (current, hidden)
                }
            }
        }

        if animated && settings.animate {
            disableEnhancedUI(for: Set(targets.keys.compactMap { windows[$0]?.pid }))
            overlays.hideTransient()
            animator.animate(targets, duration: settings.animationDuration)
        } else {
            animator.cancel()
            for (id, target) in targets {
                guard let window = windows[id] else { continue }
                if let last = window.lastApplied, last.isClose(to: target.to, tolerance: 0.5) { continue }
                let sizeChanged =
                    window.lastApplied.map {
                        abs($0.width - target.to.width) > 0.5 || abs($0.height - target.to.height) > 0.5
                    } ?? true
                apply(target.to, to: id, sizeChanged: sizeChanged)
            }
            if shouldUpdateOverlays { updateOverlays() }
        }
        onStateChange()
    }

    private func apply(_ rect: Rect, to id: WindowID, sizeChanged: Bool) {
        guard let window = windows[id] else { return }
        window.element.setFrame(CGRect(rect), sizeChanged: sizeChanged)
        window.lastApplied = rect
        lastApplyTime = CACurrentMediaTime()
    }

    /// Apps with enhanced accessibility UI turned on animate every frame change
    /// themselves, which fights the animator. Turn it off while windows move.
    private func disableEnhancedUI(for pids: Set<pid_t>) {
        for pid in pids where !enhancedUIRestore.contains(pid) {
            let app = AXUIElement.application(pid)
            if app.bool("AXEnhancedUserInterface") == true {
                app.set("AXEnhancedUserInterface", kCFBooleanFalse)
                enhancedUIRestore.insert(pid)
            }
        }
    }

    private func restoreEnhancedUI() {
        for pid in enhancedUIRestore {
            AXUIElement.application(pid).set("AXEnhancedUserInterface", kCFBooleanTrue)
        }
        enhancedUIRestore.removeAll()
    }

    private func updateOverlays() {
        guard isRunning, !isPaused else {
            overlays.hideAll()
            return
        }
        let focusedID = focusedWindowID()
        var focused: (WindowID, CGRect)?
        var inactive: [(WindowID, CGRect)] = []
        var bars: [Overlays.TabBarModel] = []

        for display in displays {
            let key = currentKey(display)
            guard let strip = strips[key], !strip.isEmpty else { continue }
            for placement in strip.layout(config: settings.layout, viewport: viewport(of: display))
            where !placement.isParked && !placement.isHiddenTab {
                guard let frame = windows[placement.window]?.lastApplied else { continue }
                if placement.window == focusedID {
                    focused = (placement.window, CGRect(frame))
                } else {
                    inactive.append((placement.window, CGRect(frame)))
                }
            }
            for bar in strip.tabBars(config: settings.layout, viewport: viewport(of: display)) {
                let tabs = bar.windows.map { id in
                    Overlays.Tab(id: id, title: windows[id].map { $0.title.isEmpty ? $0.appName : $0.title } ?? "")
                }
                bars.append(Overlays.TabBarModel(frame: CGRect(bar.frame), tabs: tabs, active: bar.active))
            }
        }
        overlays.update(focused: focused, inactive: inactive, tabBars: bars, settings: settings)
    }

    // MARK: - Focus helpers

    func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AXUIElement.application(app.processIdentifier).focusedWindow?.windowID
    }

    private func adoptFocused(_ id: WindowID) -> ManagedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let element = AXUIElement.application(app.processIdentifier).focusedWindow
        else { return nil }
        adopt(element, pid: app.processIdentifier, focus: true, force: true)
        return windows[id]
    }

    private func focus(_ id: WindowID, warpMouse: Bool) {
        guard let window = windows[id] else { return }
        window.element.set(kAXMainAttribute, kCFBooleanTrue)
        window.element.raise()
        AXUIElement.application(window.pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        if warpMouse && settings.mouseFollowsFocus, let target = targetFrame(of: id) {
            CGWarpMouseCursorPosition(CGPoint(x: target.midX, y: target.midY))
        }
    }

    private func targetFrame(of id: WindowID) -> Rect? {
        guard let key = windows[id]?.key, let strip = strips[key], let display = display(for: key) else { return nil }
        return strip.layout(config: settings.layout, viewport: viewport(of: display)).first { $0.window == id }?.frame
    }

    /// The display and strip keyboard actions apply to: the focused window's
    /// strip, or else the display under the mouse pointer.
    private func activeContext() -> (Display, StripKey)? {
        if let id = focusedWindowID(), let key = windows[id]?.key, let display = display(for: key),
            currentKey(display) == key
        {
            return (display, key)
        }
        guard let display = displayUnderMouse() ?? displays.first else { return nil }
        return (display, currentKey(display))
    }

    // MARK: - Displays

    /// The area windows are laid out in: the display's visible frame, minus
    /// room for the slider bar when it is always shown.
    private func viewport(of display: Display) -> Rect {
        var area = display.viewport
        guard settings.sliderBar == .always else { return area }
        let reserved = AppSettings.sliderBarHeight
        area.height -= reserved
        if settings.sliderBarEdge == .top { area.y += reserved }
        return area
    }

    private func currentKey(_ display: Display) -> StripKey {
        let screen = ScreenKey(display: display.uuid, space: Spaces.current(displayUUID: display.uuid))
        let workspace = min(activeWorkspace[screen] ?? 0, settings.workspaceCount - 1)
        return StripKey(screen: screen, workspace: workspace)
    }

    private func display(for key: StripKey) -> Display? {
        displays.first { $0.uuid == key.display }
    }

    private func display(containing frame: CGRect) -> Display? {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.frame.contains(centre) }
            ?? displays.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
    }

    private func displayUnderMouse() -> Display? {
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: primaryHeight - location.y)
        return displays.first { $0.frame.contains(point) }
    }

    // MARK: - Window discovery

    /// Re-reads displays, apps and windows and re-applies the layout.
    func sync() {
        guard isRunning, !isPaused else { return }
        animator.finishNow()
        refreshDisplays()

        let hiddenPIDs = Set(NSWorkspace.shared.runningApplications.filter(\.isHidden).map(\.processIdentifier))
        for (id, window) in windows {
            if !window.element.isAlive || window.element.isMinimized || window.element.isFullScreen
                || hiddenPIDs.contains(window.pid)
            {
                forget(id)
            }
        }

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != ownPID {
            syncApp(app.processIdentifier, layoutAfter: false)
        }

        // Drop restored or stale entries for windows that no longer exist on the current Spaces.
        let currentScreens = Set(displays.map { currentKey($0).screen })
        for key in strips.keys where currentScreens.contains(key.screen) {
            for id in strips[key]!.allWindows where windows[id]?.key != key {
                strips[key]!.remove(id)
            }
        }

        if let focused = focusedWindowID(), let key = windows[focused]?.key {
            strips[key]?.focus(focused)
        }
        for display in displays {
            let key = currentKey(display)
            guard var strip = strips[key] else { continue }
            strip.clampScroll(config: settings.layout, viewportWidth: viewport(of: display).width)
            strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
            strips[key] = strip
        }
        layout(animated: false)
        scheduleSave()
    }

    private func syncApp(_ pid: pid_t, layoutAfter: Bool) {
        guard pid != ownPID else { return }
        observe(pid)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let focusedID = frontmost ? AXUIElement.application(pid).focusedWindow?.windowID : nil
        var changed = false
        for element in AXUIElement.application(pid).windows {
            let id = element.windowID
            changed = adopt(element, pid: pid, focus: id != nil && id == focusedID) || changed
        }
        if changed && layoutAfter { layout(animated: true) }
    }

    private func refreshDisplays() {
        let fresh = Display.all()
        guard fresh != displays else { return }
        displays = fresh
        // Windows on displays that went away join the strip of the first display.
        let uuids = Set(displays.map(\.uuid))
        guard let fallback = displays.first else { return }
        let fallbackKey = currentKey(fallback)
        for key in Array(strips.keys) where !uuids.contains(key.display) {
            guard let orphan = strips.removeValue(forKey: key) else { continue }
            var target = strips[fallbackKey] ?? Strip()
            for column in orphan.columns {
                for id in column.windows {
                    target.insert(id, width: column.width, position: .end, focus: false)
                    windows[id]?.key = fallbackKey
                    windows[id]?.lastApplied = nil
                }
            }
            strips[fallbackKey] = target
        }
    }

    /// Starts managing `element` if it is a normal window. Returns true if a
    /// strip changed.
    @discardableResult
    private func adopt(_ element: AXUIElement, pid: pid_t, focus: Bool, force: Bool = false) -> Bool {
        guard pid != ownPID, let id = element.windowID else { return false }
        if let existing = windows[id] {
            // Known window: just follow focus.
            if focus, let key = existing.key { strips[key]?.focus(id) }
            return false
        }
        guard element.role == kAXWindowRole,
            element.subrole == kAXStandardWindowSubrole,
            !element.isMinimized, !element.isFullScreen,
            element.isSettable(kAXPositionAttribute),
            let frame = element.frame, frame.width >= 80, frame.height >= 60
        else { return false }
        let app = NSRunningApplication(processIdentifier: pid)
        guard app?.activationPolicy == .regular, app?.isHidden == false else { return false }

        if displays.isEmpty { refreshDisplays() }
        guard let display = display(containing: frame) ?? displays.first else { return false }
        let key = currentKey(display)
        let spaces = Spaces.spaces(of: id)
        if !spaces.isEmpty && key.space != 0 && !spaces.contains(key.space) { return false }

        let window = ManagedWindow(
            id: id, pid: pid, element: element,
            bundleID: app?.bundleIdentifier,
            appName: app?.localizedName ?? "App",
            home: frame
        )
        windows[id] = window
        observeWindow(element)

        // A window restored from the saved layout keeps its place.
        if let restored = strips.first(where: { $0.value.contains(id) })?.key {
            window.key = restored
            if focus { strips[restored]?.focus(id) }
            return true
        }

        let rule = settings.rule(for: window.bundleID)
        let floats = rule?.float == true || element.hasFixedSize || !element.isSettable(kAXSizeAttribute)
        if floats && !force { return false }

        place(window, in: key, display: display, focus: focus)
        return true
    }

    private func removeFromStrip(_ window: ManagedWindow) {
        guard let key = window.key, var strip = strips[key] else { return }
        strip.remove(window.id)
        if let display = display(for: key) {
            strip.clampScroll(config: settings.layout, viewportWidth: viewport(of: display).width)
            strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
        }
        strips[key] = strip
        window.key = nil
        scheduleSave()
    }

    private func forget(_ id: WindowID) {
        guard let window = windows[id] else { return }
        remember(window)
        removeFromStrip(window)
        windows[id] = nil
    }

    /// A place on a strip that a window (or an app's next window) goes back to.
    private struct Memory {
        var key: StripKey
        var slot: Strip.Slot
    }

    /// Hidden, minimised and closed windows, by window ID.
    private var windowMemory: [WindowID: Memory] = [:]
    /// Where each app's most recently removed window was, for when the app
    /// opens a window again (a Dock click after closing it, or a relaunch).
    private var appMemory: [String: Memory] = [:]

    private func remember(_ window: ManagedWindow) {
        guard let key = window.key, let slot = strips[key]?.slot(of: window.id) else { return }
        let memory = Memory(key: key, slot: slot)
        windowMemory[window.id] = memory
        appMemory[Self.appKey(window)] = memory
    }

    /// Where a returning window belongs, if MacSlider remembers. The app's
    /// slot is only used when none of its windows are on that strip, so a
    /// genuinely new second window still opens normally.
    private func memory(for window: ManagedWindow) -> Memory? {
        if let memory = windowMemory.removeValue(forKey: window.id) { return memory }
        let app = Self.appKey(window)
        guard let memory = appMemory[app] else { return nil }
        let strip = strips[memory.key] ?? Strip()
        let appOnStrip = strip.allWindows.contains { windows[$0].map(Self.appKey) == app }
        guard !appOnStrip else { return nil }
        appMemory[app] = nil
        return memory
    }

    private func window(for element: AXUIElement) -> ManagedWindow? {
        if let id = element.windowID, let window = windows[id] { return window }
        return windows.values.first { CFEqual($0.element, element) }
    }

    // MARK: - Accessibility notifications

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXTitleChangedNotification,
    ]

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let observer = created else { return }
        let app = AXUIElement.application(pid)
        var ok = false
        for name in Self.appNotifications {
            let error = AXObserverAddNotification(observer, app, name as CFString, refcon)
            ok = ok || error == .success || error == .notificationAlreadyRegistered
        }
        guard ok else {
            // The app is probably still launching; `didLaunch` and `didActivate` retry.
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func observeWindow(_ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let observer = observers[pid] else { return }
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
    }

    private func stopObserving(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        for (id, window) in windows where window.pid == pid { forget(id) }
    }

    fileprivate func handle(_ notification: String, element: AXUIElement) {
        guard isRunning, !isPaused else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        switch notification {
        case kAXWindowCreatedNotification:
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            if adopt(element, pid: pid, focus: frontmost) { layout(animated: true) }

        case kAXFocusedWindowChangedNotification:
            focusDidChange(to: element, pid: pid)

        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            if let window = window(for: element) {
                forget(window.id)
                layout(animated: true)
            }

        case kAXWindowDeminiaturizedNotification:
            if adopt(element, pid: pid, focus: true) { layout(animated: true) }

        case kAXApplicationHiddenNotification:
            for (id, window) in windows where window.pid == pid { forget(id) }
            layout(animated: true)

        case kAXApplicationShownNotification:
            syncApp(pid, layoutAfter: true)

        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            userMovedOrResized(element, resized: notification == kAXWindowResizedNotification)

        case kAXTitleChangedNotification:
            updateOverlays()

        default:
            break
        }
    }

    private func focusDidChange(to element: AXUIElement, pid: pid_t) {
        // The notification's element is usually the window; fall back to asking the app.
        let windowElement = element.role == kAXWindowRole ? element : AXUIElement.application(pid).focusedWindow
        guard let windowElement, let id = windowElement.windowID else { return }
        if windows[id] == nil {
            if adopt(windowElement, pid: pid, focus: true) { layout(animated: true) }
            return
        }
        guard swipeDisplay == nil, let window = windows[id], let key = window.key, var strip = strips[key],
            let display = display(for: key)
        else {
            updateOverlays()
            return
        }
        let switchedWorkspace = key != currentKey(display)
        if switchedWorkspace {
            // Focused (e.g. with ⌘Tab) a window parked in another workspace: show that workspace.
            showWorkspace(of: key)
        }
        strip.focus(id)
        strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
        let changed = switchedWorkspace || strip != strips[key]
        strips[key] = strip
        if changed {
            layout(animated: true)
            scheduleSave()
        } else {
            updateOverlays()
        }
    }

    /// The user dragged or resized a tiled window. Resizing changes the
    /// column width; dropping a dragged window moves its column to where it
    /// was dropped. Either way the layout is re-applied after mouse-up.
    private func userMovedOrResized(_ element: AXUIElement, resized: Bool) {
        guard !animator.isRunning, CACurrentMediaTime() - lastApplyTime > 0.3,
            let window = window(for: element), let key = window.key, let applied = window.lastApplied,
            let frame = element.frame
        else { return }
        let actual = Rect(frame)
        if resized {
            guard abs(actual.width - applied.width) > 4, let display = display(for: key) else { return }
            // A tile in a slide doesn't own the column's width; snap it back after the resize.
            if let strip = strips[key], let (c, _) = strip.locate(window.id), strip.columns[c].windows.count > 1,
                strip.columns[c].isTiled || strip.columns[c].isTabbed
            {
                whenMouseIsUp { [weak self] in self?.finishUserMove(window, resized: true) }
                return
            }
            let fraction = settings.layout.fraction(forColumnWidth: actual.width, viewportWidth: viewport(of: display).width)
            strips[key]?.setWidth(fraction, of: window.id)
        } else {
            guard abs(actual.x - applied.x) > 8 || abs(actual.y - applied.y) > 8 else { return }
        }
        whenMouseIsUp { [weak self] in self?.finishUserMove(window, resized: resized) }
    }

    private func finishUserMove(_ window: ManagedWindow, resized: Bool) {
        guard let key = window.key, var strip = strips[key], let display = display(for: key) else { return }
        if !resized, let frame = window.element.frame, let source = strip.locate(window.id)?.column {
            let frames = strip.columnFrames(config: settings.layout, viewport: viewport(of: display))
            let dropX = frame.midX
            if let target = frames.indices.first(where: { frames[$0].frame.minX <= dropX && dropX < frames[$0].frame.maxX }),
                target != source, strip.columns[target].pin == nil
            {
                strip.focus(window.id)
                if strip.columns[source].windows.count > 1 { strip.expel() }
                if let from = strip.locate(window.id)?.column { strip.moveColumn(from: from, to: target) }
            }
        }
        window.lastApplied = nil
        strip.focus(window.id)
        strip.revealFocused(config: settings.layout, viewportWidth: viewport(of: display).width)
        strips[key] = strip
        layout(animated: true)
        scheduleSave()
    }

    private func whenMouseIsUp(_ action: @escaping () -> Void) {
        mouseUpTimer?.invalidate()
        mouseUpTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons == 0 else { return }
            timer.invalidate()
            self?.mouseUpTimer = nil
            action()
        }
    }

    // MARK: - Workspace notifications

    private func registerWorkspaceNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter
        func on(
            _ name: Notification.Name, in center: NotificationCenter? = nil,
            _ block: @escaping (Notification) -> Void
        ) {
            let center = center ?? workspace
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main, using: block))
        }
        func app(_ note: Notification) -> NSRunningApplication? {
            note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        }

        on(NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            guard let pid = app(note)?.processIdentifier else { return }
            for delay in [0.3, 1.0, 2.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let self, self.isRunning, !self.isPaused else { return }
                    self.syncApp(pid, layoutAfter: true)
                }
            }
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            guard let self, let pid = app(note)?.processIdentifier else { return }
            self.stopObserving(pid)
            self.layout(animated: true)
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let self, self.isRunning, !self.isPaused, let pid = app(note)?.processIdentifier else { return }
            self.syncApp(pid, layoutAfter: true)
            if let element = AXUIElement.application(pid).focusedWindow {
                self.focusDidChange(to: element, pid: pid)
            }
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] note in
            guard let self, let pid = app(note)?.processIdentifier else { return }
            for (id, window) in self.windows where window.pid == pid { self.forget(id) }
            self.layout(animated: true)
        }
        on(NSWorkspace.didUnhideApplicationNotification) { [weak self] note in
            guard let self, let pid = app(note)?.processIdentifier else { return }
            self.syncApp(pid, layoutAfter: true)
        }
        on(NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.scheduleSync(after: 0.15) }
        on(NSWorkspace.didWakeNotification) { [weak self] _ in self?.scheduleSync(after: 1.0) }
        on(NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.scheduleSync(after: 1.0) }
        on(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in self?.scheduleSync(after: 1.0) }
        on(NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.animator.finishNow()
            self?.saveState()
        }
        on(NSApplication.didChangeScreenParametersNotification, in: .default) { [weak self] _ in
            self?.scheduleSync(after: 0.5)
        }
    }

    private func scheduleSync(after delay: TimeInterval) {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.sync() }
    }

    // MARK: - Restoring windows

    /// Pulls parked windows fully back onto their display, leaving others where they are.
    private func restoreAll() {
        for window in windows.values where window.key != nil {
            guard let frame = window.element.frame,
                let display = window.key.flatMap(display(for:)) ?? display(containing: frame)
            else { continue }
            let visible = display.visibleFrame
            var target = frame
            target.size.width = min(target.width, visible.width)
            target.size.height = min(target.height, visible.height)
            target.origin.x = min(max(target.minX, visible.minX), visible.maxX - target.width)
            target.origin.y = min(max(target.minY, visible.minY), visible.maxY - target.height)
            if target != frame { window.element.setFrame(target) }
            window.lastApplied = nil
        }
    }

    // MARK: - Persistence

    private struct SavedState: Codable {
        var strips: [StripKey: Strip]
        var activeWorkspace: [ScreenKey: Int]?
    }

    private static var stateURL: URL { SettingsStore.directory.appendingPathComponent("layout.json") }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in self?.saveState() }
    }

    /// Window IDs survive a restart of MacSlider (not of the apps), so saving
    /// the strips lets an update or relaunch pick up exactly where it left off.
    private func saveState() {
        let state = SavedState(strips: strips.filter { !$0.value.isEmpty }, activeWorkspace: activeWorkspace)
        do {
            try FileManager.default.createDirectory(at: SettingsStore.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: Self.stateURL, options: .atomic)
        } catch {
            log.error("Saving layout failed: \(error.localizedDescription)")
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: Self.stateURL),
            let state = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return }
        strips = state.strips
        activeWorkspace = state.activeWorkspace ?? [:]
    }
}

private func axObserverCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<Engine>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element: element)
}

extension Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

extension CGRect {
    init(_ rect: Rect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    var area: CGFloat { isNull ? 0 : width * height }
}
#endif
