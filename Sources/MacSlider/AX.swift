#if os(macOS)
import AppKit
import ApplicationServices

/// Returns the `CGWindowID` behind an Accessibility window element. Private,
/// but stable for many years and used by every macOS window manager.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin, typed wrappers around the Accessibility C API.
extension AXUIElement {
    static func application(_ pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    private func raw(_ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        return (error, value)
    }

    func string(_ attribute: String) -> String? {
        raw(attribute).1 as? String
    }

    func bool(_ attribute: String) -> Bool? {
        guard let value = raw(attribute).1 else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = raw(attribute).1, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func elements(_ attribute: String) -> [AXUIElement] {
        guard let value = raw(attribute).1, CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func axValue<T>(_ attribute: String, type: AXValueType, empty: T) -> T? {
        guard let value = raw(attribute).1, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = empty
        guard AXValueGetValue(value as! AXValue, type, &result) else { return nil }
        return result
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    // MARK: Common attributes

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String? { string(kAXTitleAttribute) }
    var windows: [AXUIElement] { elements(kAXWindowsAttribute) }
    var focusedWindow: AXUIElement? { element(kAXFocusedWindowAttribute) }
    var isMinimized: Bool { bool(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { bool("AXFullScreen") ?? false }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// False once the element's window or app has gone away.
    var isAlive: Bool {
        let error = raw(kAXRoleAttribute).0
        return error != .invalidUIElement && error != .cannotComplete
    }

    var position: CGPoint? { axValue(kAXPositionAttribute, type: .cgPoint, empty: CGPoint.zero) }
    var size: CGSize? { axValue(kAXSizeAttribute, type: .cgSize, empty: CGSize.zero) }

    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) { set(kAXPositionAttribute, value) }
    }

    func setSize(_ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) { set(kAXSizeAttribute, value) }
    }

    /// Moves and resizes. Size is set on both sides of the move because
    /// macOS clamps a window's size to the display it is currently on.
    func setFrame(_ frame: CGRect, sizeChanged: Bool = true) {
        if sizeChanged { setSize(frame.size) }
        setPosition(frame.origin)
        if sizeChanged { setSize(frame.size) }
    }

    func raise() {
        AXUIElementPerformAction(self, kAXRaiseAction as CFString)
    }

    /// Windows with a disabled zoom button (Calculator, many panels) have a fixed size.
    var hasFixedSize: Bool {
        guard let zoom = element(kAXZoomButtonAttribute) else { return false }
        return zoom.bool(kAXEnabledAttribute) == false
    }
}

enum Accessibility {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Bounds how long a single AX call may block on an unresponsive app.
    static func setGlobalTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }
}
#endif
