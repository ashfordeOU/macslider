/// How MacSlider treats the windows of one app.
public struct AppRule: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var bundleID: String
    /// Display name, for Settings only.
    public var name: String
    /// Keep the app's windows off the strip.
    public var float: Bool
    /// Width for new windows of this app, overriding the default width.
    public var width: Double?
    /// Where new windows of this app join the strip, overriding the default.
    public var position: Strip.InsertPosition?

    public var id: String { bundleID }

    public init(
        bundleID: String,
        name: String,
        float: Bool = false,
        width: Double? = nil,
        position: Strip.InsertPosition? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.float = float
        self.width = width
        self.position = position
    }
}

/// Number of fingers for the trackpad swipe that scrolls the strip without
/// holding modifier keys. `off` leaves three- and four-finger swipes to macOS.
public enum SwipeFingers: Int, Codable, CaseIterable, Sendable {
    case off = 0
    case three = 3
    case four = 4
}

/// User settings, persisted as JSON. Every field has a default and missing
/// fields decode to it, so older or hand-edited files keep working.
public struct AppSettings: Equatable, Codable, Sendable {
    public var layout = LayoutConfig()
    /// Animate windows into place instead of jumping.
    public var animate = true
    /// Animation length in seconds.
    public var animationDuration = 0.2
    /// Scroll the strip with a two-finger swipe while holding the shortcut modifiers.
    public var modifierSwipe = true
    /// Scroll the strip with a three- or four-finger swipe.
    public var swipeFingers: SwipeFingers = .off
    /// Multiplier applied to swipe distance.
    public var swipeSensitivity = 1.0
    /// Flip the swipe direction.
    public var invertSwipe = false
    /// Move the mouse pointer to the centre of a window focused from the keyboard.
    public var mouseFollowsFocus = false
    /// Focus the window under the mouse pointer.
    public var focusFollowsMouse = false
    /// Windows in single-window columns keep their own height, top aligned.
    public var keepHeights = false
    /// Draw a coloured border around the focused window.
    public var focusBorder = false
    public var focusBorderWidth = 3.0
    /// Hex colour of the focus border, e.g. "#4C8DFF".
    public var focusBorderColor = "#4C8DFF"
    /// Darken tiled windows that do not have focus.
    public var dimInactive = false
    /// Opacity of the dimming overlay, 0...1.
    public var dimAmount = 0.2
    /// Show "3/8" (focused column / columns) next to the menu bar icon.
    public var showColumnIndicator = true
    /// Where newly opened windows join the strip.
    public var newWindowPosition: Strip.InsertPosition = .afterFocused
    /// Per-app rules.
    public var appRules: [AppRule] = AppSettings.defaultAppRules
    public var keymap: Keymap = .default
    /// Set once the welcome tour has been shown.
    public var hasCompletedOnboarding = false

    public static let defaultAppRules = [
        AppRule(bundleID: "com.apple.systempreferences", name: "System Settings", float: true),
        AppRule(bundleID: "com.apple.calculator", name: "Calculator", float: true),
        AppRule(bundleID: "com.apple.ActivityMonitor", name: "Activity Monitor", float: true),
        AppRule(bundleID: "com.apple.archiveutility", name: "Archive Utility", float: true),
    ]

    public init() {}

    public func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID }
    }

    private enum CodingKeys: String, CodingKey {
        case layout, animate, animationDuration, modifierSwipe, swipeFingers, swipeSensitivity, invertSwipe
        case mouseFollowsFocus, focusFollowsMouse, keepHeights, focusBorder, focusBorderWidth
        case focusBorderColor, dimInactive, dimAmount, showColumnIndicator, newWindowPosition
        case appRules, keymap, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        layout = value(.layout, d.layout)
        animate = value(.animate, d.animate)
        animationDuration = value(.animationDuration, d.animationDuration)
        modifierSwipe = value(.modifierSwipe, d.modifierSwipe)
        swipeFingers = value(.swipeFingers, d.swipeFingers)
        swipeSensitivity = value(.swipeSensitivity, d.swipeSensitivity)
        invertSwipe = value(.invertSwipe, d.invertSwipe)
        mouseFollowsFocus = value(.mouseFollowsFocus, d.mouseFollowsFocus)
        focusFollowsMouse = value(.focusFollowsMouse, d.focusFollowsMouse)
        keepHeights = value(.keepHeights, d.keepHeights)
        focusBorder = value(.focusBorder, d.focusBorder)
        focusBorderWidth = value(.focusBorderWidth, d.focusBorderWidth)
        focusBorderColor = value(.focusBorderColor, d.focusBorderColor)
        dimInactive = value(.dimInactive, d.dimInactive)
        dimAmount = value(.dimAmount, d.dimAmount)
        showColumnIndicator = value(.showColumnIndicator, d.showColumnIndicator)
        newWindowPosition = value(.newWindowPosition, d.newWindowPosition)
        appRules = value(.appRules, d.appRules)
        keymap = value(.keymap, d.keymap)
        hasCompletedOnboarding = value(.hasCompletedOnboarding, d.hasCompletedOnboarding)
    }
}
