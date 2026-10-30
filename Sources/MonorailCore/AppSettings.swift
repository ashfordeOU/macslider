import Foundation

/// How Monorail treats the windows of one app.
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
    /// Workspace (0-based) this app's new windows open in.
    public var workspace: Int?
    /// Only windows whose title contains this (any case), e.g. "Meet" in a
    /// browser. Empty or nil applies to every window of the app.
    public var titleContains: String?
    /// Windows matching this rule get a slide to themselves.
    public var ownSlide: Bool?
    /// A stable identity for title rules (several can share an app).
    public var ruleID: String?

    public var id: String { ruleID ?? titleContains.map { "\(bundleID)|\($0)" } ?? bundleID }

    /// True for a rule that only applies to some window titles.
    public var isTitleRule: Bool { !(titleContains ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    public func matches(title: String) -> Bool {
        guard isTitleRule, let text = titleContains?.trimmingCharacters(in: .whitespaces) else { return true }
        return title.localizedCaseInsensitiveContains(text)
    }

    public init(
        bundleID: String,
        name: String,
        float: Bool = false,
        width: Double? = nil,
        position: Strip.InsertPosition? = nil,
        tiles: Int? = nil,
        arrangement: Arrangement? = nil,
        workspace: Int? = nil,
        titleContains: String? = nil,
        ownSlide: Bool? = nil,
        ruleID: String? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.float = float
        self.width = width
        self.position = position
        self.tiles = tiles
        self.arrangement = arrangement
        self.workspace = workspace
        self.titleContains = titleContains
        self.ownSlide = ownSlide
        self.ruleID = ruleID
    }
}

/// Settings that differ on one display (a laptop screen versus a big monitor).
public struct DisplayOverride: Equatable, Hashable, Codable, Sendable {
    /// The display's name when it was set up, for Settings.
    public var name: String
    public var gap: Double?
    public var edgeGap: Double?
    public var defaultWidth: Double?
    public var sliderBar: SliderBarMode?

    public init(name: String, gap: Double? = nil, edgeGap: Double? = nil, defaultWidth: Double? = nil,
                sliderBar: SliderBarMode? = nil) {
        self.name = name
        self.gap = gap
        self.edgeGap = edgeGap
        self.defaultWidth = defaultWidth
        self.sliderBar = sliderBar
    }
}

/// Switches profile or applies a saved layout by itself: at a time of day, or
/// when the Mac joins a Wi-Fi network.
public struct AutoRule: Equatable, Hashable, Codable, Sendable, Identifiable {
    public enum Trigger: String, Codable, CaseIterable, Sendable {
        case time, wifi
    }

    public var id: String
    public var name: String
    public var trigger: Trigger
    /// For `time`: minutes after midnight, and the weekdays (1 = Sunday … 7); empty = every day.
    public var minuteOfDay: Int
    public var weekdays: [Int]
    /// For `wifi`: the network name.
    public var network: String
    public var profile: Int?
    public var layout: String?
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString, name: String, trigger: Trigger, minuteOfDay: Int = 9 * 60,
                weekdays: [Int] = [], network: String = "", profile: Int? = nil, layout: String? = nil,
                isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.minuteOfDay = minuteOfDay
        self.weekdays = weekdays
        self.network = network
        self.profile = profile
        self.layout = layout
        self.isEnabled = isEnabled
    }

    /// True if a time rule is due at this minute of this weekday.
    public func isDue(minuteOfDay minute: Int, weekday: Int) -> Bool {
        trigger == .time && isEnabled && minute == minuteOfDay && (weekdays.isEmpty || weekdays.contains(weekday))
    }
}

/// Colours for the overview, the slider bar and workspace dots.
public enum Theme: String, Codable, CaseIterable, Sendable {
    case vivid, ocean, sunset, forest, mono

    public var title: String {
        switch self {
        case .vivid: return "Vivid"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .forest: return "Forest"
        case .mono: return "Monochrome"
        }
    }
}

/// A slide layout the user designed: columns side by side, each split into rows.
public struct CustomLayout: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Rows in each column, e.g. [1, 2] = one big tile beside two stacked.
    public var rows: [Int]

    public init(id: String = UUID().uuidString, name: String, rows: [Int]) {
        self.id = id
        self.name = name
        self.rows = rows
    }

    public var tiles: Int { rows.reduce(0, +) }
}

/// Apps that open together in one slide (like Android's app pairs).
public struct AppPair: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bundleIDs: [String]
    public var arrangement: Arrangement
    public var customRows: [Int]?

    public init(id: String = UUID().uuidString, name: String, bundleIDs: [String], arrangement: Arrangement,
                customRows: [Int]? = nil) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.arrangement = arrangement
        self.customRows = customRows
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
    /// Push the pointer against the left or right screen edge to slide.
    public var hotEdges = false
    /// Slide layouts designed in Settings.
    public var customLayouts: [CustomLayout] = [
        CustomLayout(id: "big-and-two", name: "Big + two", rows: [1, 2]),
        CustomLayout(id: "two-big-two", name: "Two, big, two", rows: [2, 1, 2]),
    ]
    /// Saved app pairs.
    public var appPairs: [AppPair] = []
    /// Profiles: whole sets of workspaces ("Work", "Home").
    public var profiles: [String] = ["Default"]
    /// Show only the workspaces in use, plus one empty one.
    public var dynamicWorkspaces = false
    /// A light tap on Force Touch trackpads when the strip settles.
    public var hapticFeedback = true
    /// Hold ⌥ and pinch on the trackpad to open (pinch in) or close the overview.
    public var pinchForOverview = true
    /// Red dots on slides whose apps show a badge in the Dock.
    public var attentionMarkers = true
    /// Dragging a window to the top of the screen shows layouts to drop it into.
    public var snapPicker = true
    /// Focus mode: how long it lasts (0 = until turned off) and how dark the rest gets.
    public var focusMinutes = 25
    public var focusDim = 0.6
    /// Overrides per display, by display UUID.
    public var displayOverrides: [String: DisplayOverride] = [:]
    public var theme: Theme = .vivid
    /// Keep settings, layouts and app pairs in iCloud Drive, shared by your Macs.
    public var syncThroughICloud = false
    /// A three-finger tap on the trackpad opens the overview.
    public var threeFingerTapOverview = false
    /// Hold ⌥ while hovering a slide in the slider to peek at it full size.
    public var peekWithOption = true
    /// Count switches and pairings on this Mac, for Insights and suggestions.
    public var collectStats = true
    /// Profile and layout changes by time of day or Wi-Fi network.
    public var autoRules: [AutoRule] = []
    /// No gaps around a lone window; wider gaps on big displays.
    public var smartGaps = false
    /// Quick launch: a letter opens or focuses an app (by bundle ID).
    public var launchSlots: [String: String] = [:]
    /// The menu bar shows the focused app's name next to the position.
    public var menuBarShowsApp = false
    /// Snap windows back when an app moves or resizes one by itself.
    public var keepWindowsInPlace = true
    /// After resizing a window in a slide, offer to rearrange the slide.
    public var resizeAssist = true
    /// Put a newly opened lone window into a slide with another app's lone
    /// window. When off, that only happens when regrouping (⌃⌥A).
    public var pairLoneWindowsOnOpen = false
    /// Layout of new slides, unless an app rule says otherwise.
    public var slideArrangement: Arrangement = .grid
    /// Workspaces per display (1...9). Each has its own strip.
    public var workspaceCount = 4
    /// Names for workspaces, by index; empty or missing means "Workspace N".
    public var workspaceNames: [String] = []
    /// Look for new versions on GitHub once a day.
    public var checkForUpdates = true
    /// Install new versions without asking (Monorail relaunches itself).
    public var installUpdatesAutomatically = false
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

    /// The rule for every window of an app (not a title rule).
    public func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID && !$0.isTitleRule }
    }

    /// The rule for one window: a title rule that matches it, else the app's rule.
    public func rule(for bundleID: String?, title: String) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID && $0.isTitleRule && $0.matches(title: title) }
            ?? rule(for: bundleID)
    }

    /// Gaps and widths on one display, with its overrides applied. With smart
    /// gaps, a lone window gets no gaps and displays 2560 points or wider get
    /// half as much again.
    public func layout(for displayUUID: String, displayWidth: Double = 0, windowCount: Int = 2) -> LayoutConfig {
        var config = layout
        if let override = displayOverrides[displayUUID] {
            if let gap = override.gap { config.gap = gap }
            if let edgeGap = override.edgeGap { config.edgeGap = edgeGap }
            if let width = override.defaultWidth { config.defaultWidth = width }
        }
        guard smartGaps else { return config }
        if windowCount <= 1 {
            config.gap = 0
            config.edgeGap = 0
        } else if displayWidth >= 2560 {
            config.gap = (config.gap * 1.5).rounded()
            config.edgeGap = (config.edgeGap * 1.5).rounded()
        }
        return config
    }

    /// Whether the slider bar shows on one display.
    public func sliderBar(for displayUUID: String) -> SliderBarMode {
        displayOverrides[displayUUID]?.sliderBar ?? sliderBar
    }

    /// Windows per slide for an app when grouping by app.
    public func tiles(for bundleID: String?) -> Int {
        min(max(rule(for: bundleID)?.tiles ?? tilesPerSlide, 1), Column.maximumWindows)
    }

    /// The name shown for workspace `index` (0-based).
    public func workspaceName(_ index: Int) -> String {
        let name = workspaceNames.indices.contains(index)
            ? workspaceNames[index].trimmingCharacters(in: .whitespaces) : ""
        return name.isEmpty ? "Workspace \(index + 1)" : name
    }

    public mutating func setWorkspaceName(_ name: String, at index: Int) {
        guard index >= 0 else { return }
        while workspaceNames.count <= index { workspaceNames.append("") }
        // Stored as typed (so a text field can hold a trailing space); trimmed when shown.
        workspaceNames[index] = name
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
        case checkForUpdates, rulesVersion, sliderBar, sliderBarEdge, slideArrangement, iconOpensSlider, pairLoneWindowsOnOpen, keepWindowsInPlace, installUpdatesAutomatically, resizeAssist, workspaceNames, hotEdges, customLayouts, appPairs, profiles, dynamicWorkspaces
        case hapticFeedback, pinchForOverview, attentionMarkers, snapPicker
        case focusMinutes, focusDim, displayOverrides, theme, syncThroughICloud, threeFingerTapOverview
        case peekWithOption, collectStats, autoRules, smartGaps, launchSlots, menuBarShowsApp
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
        // Actions added in an update get their default keys, unless those keys
        // are already taken.
        for (action, shortcuts) in Keymap.default.bindings where keymap.bindings[action] == nil {
            keymap.bindings[action] = shortcuts.filter { keymap.action(for: $0) == nil }
        }
        hasCompletedOnboarding = value(.hasCompletedOnboarding, d.hasCompletedOnboarding)
        groupByApp = value(.groupByApp, d.groupByApp)
        tilesPerSlide = min(max(value(.tilesPerSlide, d.tilesPerSlide), 1), Column.maximumWindows)
        workspaceCount = min(max(value(.workspaceCount, d.workspaceCount), 1), 9)
        checkForUpdates = value(.checkForUpdates, d.checkForUpdates)
        sliderBar = value(.sliderBar, d.sliderBar)
        slideArrangement = value(.slideArrangement, d.slideArrangement)
        sliderBarEdge = value(.sliderBarEdge, d.sliderBarEdge)
        iconOpensSlider = value(.iconOpensSlider, d.iconOpensSlider)
        pairLoneWindowsOnOpen = value(.pairLoneWindowsOnOpen, d.pairLoneWindowsOnOpen)
        keepWindowsInPlace = value(.keepWindowsInPlace, d.keepWindowsInPlace)
        resizeAssist = value(.resizeAssist, d.resizeAssist)
        workspaceNames = value(.workspaceNames, d.workspaceNames)
        hotEdges = value(.hotEdges, d.hotEdges)
        customLayouts = value(.customLayouts, d.customLayouts)
        appPairs = value(.appPairs, d.appPairs)
        profiles = value(.profiles, d.profiles)
        if profiles.isEmpty { profiles = d.profiles }
        dynamicWorkspaces = value(.dynamicWorkspaces, d.dynamicWorkspaces)
        hapticFeedback = value(.hapticFeedback, d.hapticFeedback)
        pinchForOverview = value(.pinchForOverview, d.pinchForOverview)
        attentionMarkers = value(.attentionMarkers, d.attentionMarkers)
        snapPicker = value(.snapPicker, d.snapPicker)
        focusMinutes = value(.focusMinutes, d.focusMinutes)
        focusDim = value(.focusDim, d.focusDim)
        displayOverrides = value(.displayOverrides, d.displayOverrides)
        theme = value(.theme, d.theme)
        syncThroughICloud = value(.syncThroughICloud, d.syncThroughICloud)
        threeFingerTapOverview = value(.threeFingerTapOverview, d.threeFingerTapOverview)
        peekWithOption = value(.peekWithOption, d.peekWithOption)
        collectStats = value(.collectStats, d.collectStats)
        autoRules = value(.autoRules, d.autoRules)
        smartGaps = value(.smartGaps, d.smartGaps)
        launchSlots = value(.launchSlots, d.launchSlots)
        menuBarShowsApp = value(.menuBarShowsApp, d.menuBarShowsApp)
        installUpdatesAutomatically = value(.installUpdatesAutomatically, d.installUpdatesAutomatically)
        rulesVersion = value(.rulesVersion, 1)
        if rulesVersion < Self.currentRulesVersion {
            // Version 2 added the terminal rules (four tiles per slide).
            let known = Set(appRules.map(\.bundleID))
            appRules += Self.defaultAppRules.filter { $0.tiles != nil && !known.contains($0.bundleID) }
            rulesVersion = Self.currentRulesVersion
        }
    }
}
