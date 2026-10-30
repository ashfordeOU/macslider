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
    /// How many of this app's windows share one slide when grouping by app.
    public var tiles: Int?
    /// Layout of this app's slides, overriding the default.
    public var arrangement: Arrangement?

    public var id: String { bundleID }

    public init(
        bundleID: String,
        name: String,
        float: Bool = false,
        width: Double? = nil,
        position: Strip.InsertPosition? = nil,
        tiles: Int? = nil,
        arrangement: Arrangement? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.float = float
        self.width = width
        self.position = position
        self.tiles = tiles
        self.arrangement = arrangement
    }
}

/// Number of fingers for the trackpad swipe that scrolls the strip without
/// holding modifier keys. `off` leaves three- and four-finger swipes to macOS.
public enum SwipeFingers: Int, Codable, CaseIterable, Sendable {
    case off = 0
    case three = 3
    case four = 4
}

/// When the slider bar (the mini-map of the strip) is on screen.
public enum SliderBarMode: String, Codable, CaseIterable, Sendable {
    case off
    /// Appears while the strip moves, then fades away.
    case whileMoving
    /// Always visible; windows leave room for it.
    case always
}

public enum SliderBarEdge: String, Codable, CaseIterable, Sendable {
    case top, bottom
}

/// User settings, persisted as JSON. Every field has a default and missing
/// fields decode to it, so older or hand-edited files keep working.
public struct AppSettings: Equatable, Codable, Sendable {
    public var layout = LayoutConfig()
    /// Animate windows into place instead of jumping.
    public var animate = true
    /// Animation length in seconds.
    public var animationDuration = 0.2
    /// Scroll the strip with the mouse wheel or trackpad while holding `scrollModifier`.
    public var modifierSwipe = true
    /// Keys to hold while scrolling to move the strip instead of the app under the pointer.
    public var scrollModifier: Modifiers = [.option]
    /// Scrolling over the menu bar moves the strip, no keys needed.
    public var scrollOverMenuBar = true
    /// Show clickable ‹ › buttons in the menu bar.
    public var showNavigationArrows = true
    /// Tapping this key on its own turns on slide mode.
    public var slideTrigger: SlideTrigger = .rightOption
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
    /// The slider bar: a mini-map of the strip you can drag to slide.
    public var sliderBar: SliderBarMode = .whileMoving
    public var sliderBarEdge: SliderBarEdge = .bottom
    /// Clicking the menu bar icon shows the slider; right-click shows the menu.
    public var iconOpensSlider = true
    /// Height reserved for the slider bar when it is always shown.
    public static let sliderBarHeight = 64.0
    /// Group windows into full-screen slides by app as they open.
    public var groupByApp = true
    /// Windows per slide when grouping, unless an app rule says otherwise.
    public var tilesPerSlide = 2
    /// Put a newly opened lone window into a slide with another app's lone
    /// window. When off, that only happens when regrouping (⌃⌥A).
    public var pairLoneWindowsOnOpen = false
    /// Layout of new slides, unless an app rule says otherwise.
    public var slideArrangement: Arrangement = .grid
    /// Workspaces per display (1...9). Each has its own strip.
    public var workspaceCount = 4
    /// Look for new versions on GitHub once a day.
    public var checkForUpdates = true
    /// Bumped when new default app rules ship, so existing settings pick them up once.
    public var rulesVersion = AppSettings.currentRulesVersion
    public static let currentRulesVersion = 2
    /// Set once the welcome tour has been shown.
    public var hasCompletedOnboarding = false

    public static let defaultAppRules = [
        AppRule(bundleID: "com.apple.systempreferences", name: "System Settings", float: true),
        AppRule(bundleID: "com.apple.calculator", name: "Calculator", float: true),
        AppRule(bundleID: "com.apple.ActivityMonitor", name: "Activity Monitor", float: true),
        AppRule(bundleID: "com.apple.archiveutility", name: "Archive Utility", float: true),
        AppRule(bundleID: "com.apple.Terminal", name: "Terminal", tiles: 4),
        AppRule(bundleID: "com.googlecode.iterm2", name: "iTerm", tiles: 4),
        AppRule(bundleID: "com.mitchellh.ghostty", name: "Ghostty", tiles: 4),
        AppRule(bundleID: "dev.warp.Warp-Stable", name: "Warp", tiles: 4),
        AppRule(bundleID: "net.kovidgoyal.kitty", name: "kitty", tiles: 4),
        AppRule(bundleID: "org.alacritty", name: "Alacritty", tiles: 4),
        AppRule(bundleID: "com.github.wez.wezterm", name: "WezTerm", tiles: 4),
    ]

    public init() {}

    public func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID }
    }

    /// Windows per slide for an app when grouping by app.
    public func tiles(for bundleID: String?) -> Int {
        min(max(rule(for: bundleID)?.tiles ?? tilesPerSlide, 1), 9)
    }

    /// Layout for a new slide of an app.
    public func arrangement(for bundleID: String?) -> Arrangement {
        rule(for: bundleID)?.arrangement ?? slideArrangement
    }

    private enum CodingKeys: String, CodingKey {
        case layout, animate, animationDuration, modifierSwipe, scrollModifier, scrollOverMenuBar
        case showNavigationArrows, slideTrigger, swipeFingers, swipeSensitivity, invertSwipe
        case mouseFollowsFocus, focusFollowsMouse, keepHeights, focusBorder, focusBorderWidth
        case focusBorderColor, dimInactive, dimAmount, showColumnIndicator, newWindowPosition
        case appRules, keymap, hasCompletedOnboarding, groupByApp, tilesPerSlide, workspaceCount
        case checkForUpdates, rulesVersion, sliderBar, sliderBarEdge, slideArrangement, iconOpensSlider, pairLoneWindowsOnOpen
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
        scrollModifier = value(.scrollModifier, d.scrollModifier)
        scrollOverMenuBar = value(.scrollOverMenuBar, d.scrollOverMenuBar)
        showNavigationArrows = value(.showNavigationArrows, d.showNavigationArrows)
        slideTrigger = value(.slideTrigger, d.slideTrigger)
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
        groupByApp = value(.groupByApp, d.groupByApp)
        tilesPerSlide = min(max(value(.tilesPerSlide, d.tilesPerSlide), 1), 9)
        workspaceCount = min(max(value(.workspaceCount, d.workspaceCount), 1), 9)
        checkForUpdates = value(.checkForUpdates, d.checkForUpdates)
        sliderBar = value(.sliderBar, d.sliderBar)
        slideArrangement = value(.slideArrangement, d.slideArrangement)
        sliderBarEdge = value(.sliderBarEdge, d.sliderBarEdge)
        iconOpensSlider = value(.iconOpensSlider, d.iconOpensSlider)
        pairLoneWindowsOnOpen = value(.pairLoneWindowsOnOpen, d.pairLoneWindowsOnOpen)
        rulesVersion = value(.rulesVersion, 1)
        if rulesVersion < Self.currentRulesVersion {
            // Version 2 added the terminal rules (four tiles per slide).
            let known = Set(appRules.map(\.bundleID))
            appRules += Self.defaultAppRules.filter { $0.tiles != nil && !known.contains($0.bundleID) }
            rulesVersion = Self.currentRulesVersion
        }
    }
}
