#if os(macOS)
import AppKit
import Combine
import MonorailCore
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, layout, input, appearance, apps, automation, insights, shortcuts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .input: return "Motion & Input"
        case .appearance: return "Appearance"
        case .apps: return "Apps"
        case .automation: return "Automation"
        case .insights: return "Insights"
        case .shortcuts: return "Shortcuts"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.split.3x1"
        case .input: return "hand.draw"
        case .appearance: return "paintbrush"
        case .apps: return "square.grid.2x2"
        case .automation: return "clock.arrow.2.circlepath"
        case .insights: return "chart.bar"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var stats: UsageStats
    let isPaused: () -> Bool
    let setPaused: (Bool) -> Void

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralPane(store: store, isPaused: isPaused, setPaused: setPaused)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }
                .tag(SettingsTab.general)
            LayoutPane(store: store)
                .tabItem { Label(SettingsTab.layout.title, systemImage: SettingsTab.layout.symbol) }
                .tag(SettingsTab.layout)
            InputPane(store: store)
                .tabItem { Label(SettingsTab.input.title, systemImage: SettingsTab.input.symbol) }
                .tag(SettingsTab.input)
            AppearancePane(store: store)
                .tabItem { Label(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.symbol) }
                .tag(SettingsTab.appearance)
            AppsPane(store: store)
                .tabItem { Label(SettingsTab.apps.title, systemImage: SettingsTab.apps.symbol) }
                .tag(SettingsTab.apps)
            AutomationPane(store: store)
                .tabItem { Label(SettingsTab.automation.title, systemImage: SettingsTab.automation.symbol) }
                .tag(SettingsTab.automation)
            InsightsPane(store: store, stats: stats)
                .tabItem { Label(SettingsTab.insights.title, systemImage: SettingsTab.insights.symbol) }
                .tag(SettingsTab.insights)
            ShortcutsPane(store: store)
                .tabItem { Label(SettingsTab.shortcuts.title, systemImage: SettingsTab.shortcuts.symbol) }
                .tag(SettingsTab.shortcuts)
            AboutPane()
                .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.symbol) }
                .tag(SettingsTab.about)
        }
        .frame(width: 780, height: 640)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var store: SettingsStore
    let isPaused: () -> Bool
    let setPaused: (Bool) -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var paused = false
    @State private var checks: [SetupCheck] = []

    var body: some View {
        Form {
            Section {
                Toggle("Launch Monorail at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LoginItem.setEnabled($0) }
                Toggle("Pause tiling", isOn: $paused)
                    .onChange(of: paused) { setPaused($0) }
                Toggle("Show column position in the menu bar", isOn: $store.settings.showColumnIndicator)
                Toggle("Show the focused app’s name in the menu bar too", isOn: $store.settings.menuBarShowsApp)
                    .disabled(!store.settings.showColumnIndicator)
                Toggle("Clicking the menu bar icon shows the slider (right-click for the menu)", isOn: $store.settings.iconOpensSlider)
                Stepper(value: $store.settings.workspaceCount, in: 1...9) {
                    Text("Workspaces per display: \(store.settings.workspaceCount)")
                }
                ForEach(0..<store.settings.workspaceCount, id: \.self) { index in
                    LabeledContent {
                        TextField("Workspace \(index + 1)", text: workspaceName(index))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(WorkspaceColor.color(index)).frame(width: 9, height: 9)
                            Text("Name of workspace \(index + 1)")
                        }
                    }
                }
                Toggle("Only show workspaces in use, plus one empty one", isOn: $store.settings.dynamicWorkspaces)
                Toggle("Red dots on windows whose apps have a badge in the Dock", isOn: $store.settings.attentionMarkers)
                Toggle("Check for updates automatically", isOn: $store.settings.checkForUpdates)
                Toggle("Install updates automatically", isOn: $store.settings.installUpdatesAutomatically)
                    .disabled(!store.settings.checkForUpdates)
                Picker("New windows open", selection: $store.settings.newWindowPosition) {
                    Text("Next to the focused window").tag(Strip.InsertPosition.afterFocused)
                    Text("At the end of the strip").tag(Strip.InsertPosition.end)
                    Text("At the start of the strip").tag(Strip.InsertPosition.start)
                }
            }
            ProfilesSection(store: store)
            SyncSection(store: store)
            RestoreSection(store: store)
            Section {
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: check.state == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(check.state == .ok ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title).fontWeight(.medium)
                            Text(check.detail).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if let url = check.fixURL {
                            Button("Open…") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
                Button("Check again") { refresh() }
            } header: {
                Text("Mac setup")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            paused = isPaused()
            launchAtLogin = LoginItem.isEnabled
            refresh()
        }
    }

    private func refresh() { checks = SetupCheck.run(settings: store.settings) }

    private func workspaceName(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                store.settings.workspaceNames.indices.contains(index) ? store.settings.workspaceNames[index] : ""
            },
            set: { store.settings.setWorkspaceName($0, at: index) }
        )
    }
}

// MARK: - Layout

private let widthChoices: [(String, Double)] = [
    ("¼", 0.25), ("⅓", 1.0 / 3.0), ("½", 0.5), ("⅔", 2.0 / 3.0), ("¾", 0.75), ("Full", 1.0),
]

private struct LayoutPane: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Strip direction", selection: $store.settings.layout.direction) {
                    ForEach(StripDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Keep windows in place when an app resizes or moves them itself", isOn: $store.settings.keepWindowsInPlace)
                Toggle("After resizing a window in a slide, offer to rearrange it", isOn: $store.settings.resizeAssist)
                Toggle("Group windows into slides by app", isOn: $store.settings.groupByApp)
                Toggle("Pair lone windows of different apps as they open", isOn: $store.settings.pairLoneWindowsOnOpen)
                    .disabled(!store.settings.groupByApp)
                Stepper(value: $store.settings.tilesPerSlide, in: 1...Column.maximumWindows) {
                    Text("Windows per slide: \(store.settings.tilesPerSlide)")
                }
                .disabled(!store.settings.groupByApp)
                Toggle("Drag a window to the top of the screen to pick a snap layout", isOn: $store.settings.snapPicker)
                Picker("Slide layout", selection: $store.settings.slideArrangement) {
                    ForEach(Arrangement.standard, id: \.self) { arrangement in
                        Label(arrangement.title, systemImage: arrangement.symbol).tag(arrangement)
                    }
                }
            } header: {
                Text("Slides")
            } footer: {
                Text("Windows of the same app share a full-screen slide. Lone windows of different apps pair up when you regroup, or as they open if you turn that on. Windows that come back — unhidden, unminimised, reopened from the Dock or after a relaunch — return to exactly where they were. Terminals get four tiles per slide — change tiles and layout per app under Apps. ⌃⌥A regroups everything; ⌃⌥G cycles a slide through Grid, Columns, Main + side, Main + bottom and Rows; ⌃⌥. and ⌃⌥, resize the main window; ⌃⌥M makes a window the main one. Right to left mirrors the whole strip.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            CustomLayoutsSection(store: store)
            Section("Spacing") {
                LabeledSlider(title: "Gap between windows", value: $store.settings.layout.gap, range: 0...40)
                LabeledSlider(title: "Gap at screen edges", value: $store.settings.layout.edgeGap, range: 0...40)
                Toggle("Smart gaps: none around a lone window, wider on big displays", isOn: $store.settings.smartGaps)
            }
            DisplaysSection(store: store)
            Section("Widths") {
                Picker("New window width", selection: $store.settings.layout.defaultWidth) {
                    ForEach(widthChoices, id: \.1) { Text($0.0).tag($0.1) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("“Cycle width” steps through")
                    HStack {
                        ForEach(widthChoices, id: \.1) { choice in
                            Toggle(choice.0, isOn: presetBinding(choice.1)).toggleStyle(.button)
                        }
                    }
                }
            }
            Section("Scrolling") {
                Picker("Centre the focused window", selection: $store.settings.layout.centerMode) {
                    Text("Never — scroll just enough").tag(CenterMode.never)
                    Text("When it would be off-screen").tag(CenterMode.onOverflow)
                    Text("Always").tag(CenterMode.always)
                }
            }
            Section("Windows") {
                Toggle("Keep each window’s own height", isOn: $store.settings.keepHeights)
                LabeledSlider(title: "Tab bar height", value: $store.settings.layout.tabBarHeight, range: 20...44)
            }
        }
        .formStyle(.grouped)
    }

    private func presetBinding(_ value: Double) -> Binding<Bool> {
        Binding(
            get: { store.settings.layout.widthPresets.contains { abs($0 - value) < 0.001 } },
            set: { on in
                var presets = store.settings.layout.widthPresets.filter { abs($0 - value) >= 0.001 }
                if on { presets.append(value) }
                if presets.isEmpty { return }
                store.settings.layout.widthPresets = presets.sorted()
            }
        )
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: 1).frame(width: 200)
                Text("\(Int(value)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: - Motion & input

private struct InputPane: View {
    @ObservedObject var store: SettingsStore
    static let scrollModifiers: [Modifiers] = [[.option], [.command], [.control], [.control, .option]]

    var body: some View {
        Form {
            Section("Animation") {
                Toggle("Animate windows", isOn: $store.settings.animate)
                LabeledContent("Speed") {
                    Picker("", selection: $store.settings.animationDuration) {
                        Text("Fast").tag(0.12)
                        Text("Normal").tag(0.2)
                        Text("Relaxed").tag(0.3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                .disabled(!store.settings.animate)
            }
            Section {
                Picker("Slide mode key", selection: $store.settings.slideTrigger) {
                    ForEach(SlideTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Slide mode")
            } footer: {
                Text("Tap this key on its own, then use plain keys: ← → to slide, ⇧← ⇧→ to move a window, R width, F fill, C centre, 1–9 jump. Esc, Return or a few idle seconds end it. You can also scroll the strip while it’s on.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $store.settings.modifierSwipe) {
                    HStack {
                        Text("Scroll the strip while holding")
                        Picker("", selection: $store.settings.scrollModifier) {
                            ForEach(Self.scrollModifiers, id: \.rawValue) { Text($0.symbols).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                Toggle("Scroll the strip when the pointer is over the menu bar", isOn: $store.settings.scrollOverMenuBar)
                Toggle("Show ‹ › buttons in the menu bar", isOn: $store.settings.showNavigationArrows)
                Picker("Swipe without any keys", selection: $store.settings.swipeFingers) {
                    Text("Off").tag(SwipeFingers.off)
                    Text("Three fingers").tag(SwipeFingers.three)
                    Text("Four fingers").tag(SwipeFingers.four)
                }
                LabeledContent("Sensitivity") {
                    Slider(value: $store.settings.swipeSensitivity, in: 0.25...3).frame(width: 240)
                }
                Toggle("Reverse scroll direction", isOn: $store.settings.invertSwipe)
            } header: {
                Text("Mouse & trackpad scrolling")
            } footer: {
                Text("With a mouse, each notch of the wheel moves one window. On a trackpad the strip follows your fingers and settles on the nearest window. If macOS uses the same finger count to switch Spaces, change it in System Settings → Trackpad → More Gestures.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Hot edges: rest the pointer on the left or right screen edge to slide", isOn: $store.settings.hotEdges)
                Toggle("Hold ⌥ and pinch on the trackpad for the overview", isOn: $store.settings.pinchForOverview)
                Toggle("Tap with three fingers for the overview", isOn: $store.settings.threeFingerTapOverview)
                    .help("If macOS uses a three-finger tap for Look Up, change that in System Settings → Trackpad")
                Toggle("Hold ⌥ over a slide in the slider to peek at it", isOn: $store.settings.peekWithOption)
                Toggle("Haptic tap as the strip lands on a slide (Force Touch trackpads)", isOn: $store.settings.hapticFeedback)
            } header: {
                Text("Gestures & screen edges")
            }
            Section("Focus") {
                Toggle("Focus follows mouse", isOn: $store.settings.focusFollowsMouse)
                Toggle("Mouse follows focus", isOn: $store.settings.mouseFollowsFocus)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @ObservedObject var store: SettingsStore

    private var sliderBarOn: Binding<Bool> {
        Binding(
            get: { store.settings.sliderBar != .off },
            set: { store.settings.sliderBar = $0 ? .always : .off })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show the slider bar", isOn: sliderBarOn)
                if store.settings.sliderBar != .off {
                    Picker("Show it", selection: $store.settings.sliderBar) {
                        Text("Always (windows leave room for it)").tag(SliderBarMode.always)
                        Text("Only while sliding").tag(SliderBarMode.whileMoving)
                    }
                    Picker("Position", selection: $store.settings.sliderBarEdge) {
                        Text("Bottom of the screen").tag(SliderBarEdge.bottom)
                        Text("Top of the screen").tag(SliderBarEdge.top)
                    }
                }
            } header: {
                Text("Slider bar")
            } footer: {
                Text("A mini-map of every slide in the workspace: drag it to slide your windows along, click a slide to jump to it. Turn it off to use just the menu bar icon; windows then fill the screen right down to the Dock.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Theme") {
                Picker("Colours", selection: $store.settings.theme) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { i in
                                Circle().fill(WorkspaceColor.palette(theme)[i]).frame(width: 9, height: 9)
                            }
                            Text(theme.title).padding(.leading, 4)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                Picker("Lasts", selection: $store.settings.focusMinutes) {
                    Text("Until I turn it off").tag(0)
                    ForEach([15, 25, 45, 60, 90], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                LabeledContent("Dim everything else") {
                    Slider(value: $store.settings.focusDim, in: 0.2...0.9).frame(width: 240)
                }
            } header: {
                Text("Focus mode")
            } footer: {
                Text("⌃⌥B dims every window except the slide you’re in, so the rest of the strip fades away. It ends by itself after the time you choose.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Focus border") {
                Toggle("Outline the focused window", isOn: $store.settings.focusBorder)
                ColorPicker("Colour", selection: borderColor, supportsOpacity: false)
                    .disabled(!store.settings.focusBorder)
                LabeledContent("Width") {
                    Stepper(value: $store.settings.focusBorderWidth, in: 1...10, step: 1) {
                        Text("\(Int(store.settings.focusBorderWidth)) pt").monospacedDigit()
                    }
                }
                .disabled(!store.settings.focusBorder)
            }
            Section("Inactive windows") {
                Toggle("Dim windows that don’t have focus", isOn: $store.settings.dimInactive)
                LabeledContent("Amount") {
                    Slider(value: $store.settings.dimAmount, in: 0.05...0.6).frame(width: 240)
                }
                .disabled(!store.settings.dimInactive)
            }
        }
        .formStyle(.grouped)
    }

    private var borderColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: store.settings.focusBorderColor) ?? .controlAccentColor) },
            set: { store.settings.focusBorderColor = NSColor($0).hexString }
        )
    }
}

// MARK: - Apps

private struct AppsPane: View {
    @ObservedObject var store: SettingsStore

    private var allRunningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func titleBinding(_ rule: Binding<AppRule>) -> Binding<String> {
        Binding(get: { rule.wrappedValue.titleContains ?? "" }, set: { rule.wrappedValue.titleContains = $0 })
    }

    private var runningApps: [NSRunningApplication] {
        let known = Set(store.settings.appRules.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !known.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        Form {
            Section {
                ForEach($store.settings.appRules) { $rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(rule.name).fontWeight(.medium)
                            if rule.ruleID != nil || rule.isTitleRule {
                                TextField("Only windows whose title contains…", text: titleBinding($rule))
                                    .textFieldStyle(.roundedBorder).frame(width: 220)
                            } else {
                                Text(rule.bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                store.settings.appRules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack(spacing: 16) {
                            Toggle("Float", isOn: $rule.float)
                            Toggle("Own slide", isOn: Binding(
                                get: { rule.ownSlide ?? false }, set: { rule.ownSlide = $0 ? true : nil }))
                                .disabled(rule.float)
                            Picker("Width", selection: $rule.width) {
                                Text("Default").tag(Double?.none)
                                ForEach(widthChoices, id: \.1) { Text($0.0).tag(Double?.some($0.1)) }
                            }
                            .frame(width: 150)
                            .disabled(rule.float)
                            Picker("Opens", selection: $rule.position) {
                                Text("Default").tag(Strip.InsertPosition?.none)
                                Text("Next").tag(Strip.InsertPosition?.some(.afterFocused))
                                Text("Start").tag(Strip.InsertPosition?.some(.start))
                                Text("End").tag(Strip.InsertPosition?.some(.end))
                            }
                            .frame(width: 150)
                            .disabled(rule.float)
                        }
                        HStack(spacing: 16) {
                            Picker("Per slide", selection: $rule.tiles) {
                                Text("Default").tag(Int?.none)
                                ForEach(1...Column.maximumWindows, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                            }
                            .frame(width: 130)
                            .disabled(rule.float)
                            Picker("Workspace", selection: $rule.workspace) {
                                Text("Current").tag(Int?.none)
                                ForEach(0..<store.settings.workspaceCount, id: \.self) { index in
                                    Text(store.settings.workspaceName(index)).tag(Int?.some(index))
                                }
                            }
                            .frame(width: 190)
                            .disabled(rule.float)
                            Picker("Layout", selection: $rule.arrangement) {
                                Text("Default").tag(Arrangement?.none)
                                ForEach(Arrangement.standard, id: \.self) { Text($0.title).tag(Arrangement?.some($0)) }
                            }
                            .frame(width: 200)
                            .disabled(rule.float)
                        }
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Menu("Add a running app…") {
                        ForEach(runningApps, id: \.processIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                store.settings.appRules.append(
                                    AppRule(bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!))
                            }
                        }
                    }
                    Menu("Add a rule by window title…") {
                        ForEach(allRunningApps, id: \.processIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                store.settings.appRules.append(AppRule(
                                    bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!,
                                    titleContains: "", ruleID: UUID().uuidString))
                            }
                        }
                    }
                }
            } header: {
                Text("Per-app rules")
            } footer: {
                Text("Floating apps stay where you put them. Dialogs, panels and fixed-size windows always float. A title rule only applies to windows whose title contains its words (a browser window titled “Meet”), and takes over when the title changes. Rules apply to windows opened after the change; press ⌃⌥T to float or tile a window right now.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            QuickLaunchSection(store: store, apps: allRunningApps)
            Section {
                if store.settings.appPairs.isEmpty {
                    Text("No app pairs yet.").foregroundStyle(.secondary)
                }
                ForEach($store.settings.appPairs) { $pair in
                    HStack {
                        Image(systemName: pair.arrangement.symbol)
                        TextField("Name", text: $pair.name).textFieldStyle(.roundedBorder).frame(width: 200)
                        Text(pair.bundleIDs.map(Self.appName).joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button {
                            store.settings.appPairs.removeAll { $0.id == pair.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("App pairs")
            } footer: {
                Text("Right-click a window in a slide’s preview or the overview and choose Save Slide as App Pair. Open a pair from App Pairs in the menu bar: Monorail launches its apps and puts them in one slide.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

extension AppsPane {
    static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
    }
}

// MARK: - Restore

private struct RestoreSection: View {
    @ObservedObject var store: SettingsStore
    @State private var confirming = false
    @State private var done = false

    var body: some View {
        Section {
            HStack {
                Button("Restore All Settings to Defaults…") { confirming = true }
                if done { Label("Restored", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            .confirmationDialog("Restore all settings to their defaults?", isPresented: $confirming) {
                Button("Restore Defaults", role: .destructive) {
                    store.restoreAllDefaults()
                    done = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { done = false }
                }
            } message: {
                Text("Shortcuts, gestures, layout and appearance go back to how Monorail comes. Your workspace and profile names, rules, app pairs, layouts and quick launch letters stay.")
            }
        } footer: {
            Text("Export your settings first if you might want them back.").font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sync, export and import

private struct SyncSection: View {
    @ObservedObject var store: SettingsStore
    @State private var message = ""

    var body: some View {
        Section {
            Toggle("Sync settings, layouts and app pairs through iCloud Drive", isOn: $store.settings.syncThroughICloud)
                .disabled(SettingsStore.cloudURL == nil)
            HStack {
                Button("Export Settings…") { export() }
                Button("Import Settings…") { importFile() }
                if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
        } header: {
            Text("Your Macs")
        } footer: {
            Text(SettingsStore.cloudURL == nil
                 ? "Turn on iCloud Drive in System Settings to sync. Export makes one file with your settings, shortcuts, rules, app pairs and saved layouts, to share or keep."
                 : "Syncing keeps a file in iCloud Drive ▸ Monorail and checks it every minute. Each Mac keeps its own display settings. Export makes one file with everything, to share or keep.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Monorail Settings.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            message = "Exported."
        } catch {
            message = "Couldn’t export: \(error.localizedDescription)"
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importBundle(from: url)
            message = "Imported."
        } catch {
            message = "That file isn’t a Monorail settings file."
        }
    }
}

// MARK: - Per display

/// Gaps, new-window width and the slider bar for each connected display.
private struct DisplaysSection: View {
    @ObservedObject var store: SettingsStore
    private let displays = Display.all()

    var body: some View {
        Section {
            ForEach(displays, id: \.uuid) { display in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: hasOverride(display)) {
                        Text(display.name).fontWeight(.medium)
                        + Text("  \(Int(display.frame.width)) × \(Int(display.frame.height))").foregroundColor(.secondary)
                    }
                    if store.settings.displayOverrides[display.uuid] != nil {
                        LabeledSlider(title: "Gap between windows", value: value(display, \.gap, store.settings.layout.gap), range: 0...40)
                        LabeledSlider(title: "Gap at screen edges", value: value(display, \.edgeGap, store.settings.layout.edgeGap), range: 0...40)
                        Picker("New window width", selection: value(display, \.defaultWidth, store.settings.layout.defaultWidth)) {
                            ForEach(widthChoices, id: \.1) { Text($0.0).tag($0.1) }
                        }
                        Picker("Slider bar", selection: barBinding(display)) {
                            Text("Same as everywhere").tag(SliderBarMode?.none)
                            Text("Always").tag(SliderBarMode?.some(.always))
                            Text("Only while sliding").tag(SliderBarMode?.some(.whileMoving))
                            Text("Off").tag(SliderBarMode?.some(.off))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Displays")
        } footer: {
            Text("Give a display its own settings, say wider gaps and no slider bar on a big monitor.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func hasOverride(_ display: Display) -> Binding<Bool> {
        Binding(
            get: { store.settings.displayOverrides[display.uuid] != nil },
            set: { on in
                store.settings.displayOverrides[display.uuid] = on ? DisplayOverride(name: display.name) : nil
            })
    }

    private func value(_ display: Display, _ path: WritableKeyPath<DisplayOverride, Double?>, _ fallback: Double) -> Binding<Double> {
        Binding(
            get: { store.settings.displayOverrides[display.uuid]?[keyPath: path] ?? fallback },
            set: { store.settings.displayOverrides[display.uuid]?[keyPath: path] = $0 })
    }

    private func barBinding(_ display: Display) -> Binding<SliderBarMode?> {
        Binding(
            get: { store.settings.displayOverrides[display.uuid]?.sliderBar },
            set: { store.settings.displayOverrides[display.uuid]?.sliderBar = $0 })
    }
}

// MARK: - Quick launch

/// ⌃⌥U then a letter opens an app, or goes to its window.
private struct QuickLaunchSection: View {
    @ObservedObject var store: SettingsStore
    let apps: [NSRunningApplication]
    @State private var letter = "t"

    private static let letters = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init)

    var body: some View {
        Section {
            ForEach(store.settings.launchSlots.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    Text(UsageStats.appName(store.settings.launchSlots[key] ?? ""))
                    Spacer()
                    Button {
                        store.settings.launchSlots[key] = nil
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                Picker("Letter", selection: $letter) {
                    ForEach(Self.letters, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                .frame(width: 120)
                Menu("Assign a running app…") {
                    ForEach(apps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            store.settings.launchSlots[letter] = app.bundleIdentifier
                        }
                    }
                }
            }
        } header: {
            Text("Quick launch")
        } footer: {
            Text("Press ⌃⌥U, then the letter: Monorail goes to that app’s window, or opens the app if it isn’t running.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Automation

private struct AutomationPane: View {
    @ObservedObject var store: SettingsStore

    private static let weekdayNames = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        Form {
            Section {
                ForEach($store.settings.autoRules) { $rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("", isOn: $rule.isEnabled).labelsHidden()
                            TextField("Name", text: $rule.name).textFieldStyle(.roundedBorder).frame(width: 180)
                            Picker("", selection: $rule.trigger) {
                                Text("At a time").tag(AutoRule.Trigger.time)
                                Text("On Wi-Fi").tag(AutoRule.Trigger.wifi)
                            }
                            .labelsHidden()
                            .frame(width: 120)
                            Spacer()
                            Button {
                                store.settings.autoRules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack(spacing: 12) {
                            if rule.trigger == .time {
                                DatePicker("", selection: timeBinding($rule), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                HStack(spacing: 3) {
                                    ForEach(1...7, id: \.self) { day in
                                        let on = rule.weekdays.contains(day)
                                        Button(Self.weekdayNames[day - 1]) {
                                            if on { rule.weekdays.removeAll { $0 == day } } else { rule.weekdays.append(day) }
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                                        .foregroundStyle(on ? Color.white : Color.primary)
                                    }
                                }
                                .help("Days it runs; none means every day")
                            } else {
                                TextField("Network name", text: $rule.network).textFieldStyle(.roundedBorder).frame(width: 180)
                                if let current = AutoRules.currentNetwork() {
                                    Button("Use “\(current)”") { rule.network = current }
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            Picker("Profile", selection: $rule.profile) {
                                Text("Keep").tag(Int?.none)
                                ForEach(store.settings.profiles.indices, id: \.self) { Text(store.settings.profiles[$0]).tag(Int?.some($0)) }
                            }
                            .frame(width: 200)
                            Picker("Layout", selection: layoutBinding($rule)) {
                                Text("Keep").tag("")
                                ForEach(layoutNames, id: \.self) { Text($0).tag($0) }
                            }
                            .frame(width: 220)
                        }
                    }
                    .padding(.vertical, 3)
                }
                HStack {
                    Button("Add Time Rule") {
                        store.settings.autoRules.append(AutoRule(name: "Mornings", trigger: .time, weekdays: [2, 3, 4, 5, 6]))
                    }
                    Button("Add Wi-Fi Rule") {
                        store.settings.autoRules.append(AutoRule(
                            name: "Office", trigger: .wifi, network: AutoRules.currentNetwork() ?? ""))
                    }
                }
            } header: {
                Text("Auto rules")
            } footer: {
                Text("Switch profile or apply a saved layout at a time of day, or when you join a Wi-Fi network. macOS asks for Location access the first time, because it only tells apps the network’s name with that permission.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ForEach(Self.urls.indices, id: \.self) { index in
                    let (url, what) = Self.urls[index]
                    HStack {
                        Text(url).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Text(what).font(.callout).foregroundStyle(.secondary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                }
            } header: {
                Text("Shortcuts app, scripts and Raycast")
            } footer: {
                Text("In the Shortcuts app add “Open URLs” with one of these; in a script use open \"monorail://…\". Every action in the Shortcuts list works too, like monorail://focus-left.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static let urls: [(String, String)] = [
        ("monorail://layout/Coding", "apply a saved layout"),
        ("monorail://pair/Safari + Notes", "open an app pair"),
        ("monorail://snapshot/Friday", "restore a snapshot"),
        ("monorail://save-snapshot/Friday", "take a snapshot"),
        ("monorail://profile/Work", "switch profile"),
        ("monorail://workspace/2", "go to a workspace"),
        ("monorail://focus-mode/on", "focus mode on or off"),
        ("monorail://launch/t", "quick launch"),
        ("monorail://palette", "command palette"),
    ]

    private var layoutNames: [String] {
        ((try? Data(contentsOf: SettingsStore.layoutsURL))
            .flatMap { try? JSONDecoder().decode([SavedLayout].self, from: $0) } ?? [])
            .filter { $0.isSnapshot != true }.map(\.name)
    }

    private func layoutBinding(_ rule: Binding<AutoRule>) -> Binding<String> {
        Binding(get: { rule.wrappedValue.layout ?? "" }, set: { rule.wrappedValue.layout = $0.isEmpty ? nil : $0 })
    }

    private func timeBinding(_ rule: Binding<AutoRule>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: rule.wrappedValue.minuteOfDay / 60, minute: rule.wrappedValue.minuteOfDay % 60,
                    second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.wrappedValue.minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}

// MARK: - Profiles

/// Profiles: whole sets of workspaces, like separate desks for work and home.
private struct ProfilesSection: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section {
            ForEach(store.settings.profiles.indices, id: \.self) { index in
                HStack {
                    TextField("Profile \(index + 1)", text: name(index)).textFieldStyle(.roundedBorder).frame(width: 220)
                    Spacer()
                    if store.settings.profiles.count > 1 {
                        Button {
                            store.settings.profiles.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button("Add Profile") { store.settings.profiles.append("Profile \(store.settings.profiles.count + 1)") }
                .disabled(store.settings.profiles.count >= 9)
        } header: {
            Text("Profiles")
        } footer: {
            Text("Each profile has its own workspaces and windows. Switch with ⌃⌥0 or from the menu bar; the other profiles’ windows wait out of sight.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func name(_ index: Int) -> Binding<String> {
        Binding(
            get: { store.settings.profiles.indices.contains(index) ? store.settings.profiles[index] : "" },
            set: { if store.settings.profiles.indices.contains(index) { store.settings.profiles[index] = $0 } }
        )
    }
}

// MARK: - Custom layouts

/// Design slide layouts: columns side by side, each split into rows.
private struct CustomLayoutsSection: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section {
            ForEach($store.settings.customLayouts) { $layout in
                HStack(alignment: .center, spacing: 14) {
                    LayoutDiagram(rows: layout.rows).frame(width: 84, height: 52)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name", text: $layout.name).textFieldStyle(.roundedBorder).frame(width: 200)
                        HStack(spacing: 10) {
                            ForEach(layout.rows.indices, id: \.self) { column in
                                Stepper(value: rowBinding($layout, column), in: 1...4) {
                                    Text("\(layout.rows[column])").monospacedDigit()
                                }
                                .fixedSize()
                                .help("Rows in column \(column + 1)")
                            }
                            Button {
                                if layout.tiles < Column.maximumWindows { layout.rows.append(1) }
                            } label: {
                                Image(systemName: "plus.rectangle")
                            }
                            .buttonStyle(.borderless)
                            .help("Add a column")
                            .disabled(layout.rows.count >= 4 || layout.tiles >= Column.maximumWindows)
                            Button {
                                if layout.rows.count > 1 { layout.rows.removeLast() }
                            } label: {
                                Image(systemName: "minus.rectangle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove the last column")
                            .disabled(layout.rows.count <= 1)
                        }
                    }
                    Spacer()
                    Button {
                        store.settings.customLayouts.removeAll { $0.id == layout.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("New Layout") {
                store.settings.customLayouts.append(CustomLayout(name: "My layout", rows: [1, 2]))
            }
        } header: {
            Text("Custom slide layouts")
        } footer: {
            Text("Each column is split into the number of rows shown (up to six windows a slide). Use them from a slide’s right-click menu ▸ Slide Layout.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Rows of one column, kept within six windows in all.
    private func rowBinding(_ layout: Binding<CustomLayout>, _ column: Int) -> Binding<Int> {
        Binding(
            get: { layout.wrappedValue.rows.indices.contains(column) ? layout.wrappedValue.rows[column] : 1 },
            set: { value in
                guard layout.wrappedValue.rows.indices.contains(column) else { return }
                let others = layout.wrappedValue.tiles - layout.wrappedValue.rows[column]
                layout.wrappedValue.rows[column] = min(value, Column.maximumWindows - others)
            }
        )
    }
}

/// A small drawing of a custom layout.
private struct LayoutDiagram: View {
    let rows: [Int]

    var body: some View {
        GeometryReader { geometry in
            let frames = Arrangement.customFrames(count: max(rows.reduce(0, +), 1), rows: rows)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, unit in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor.opacity(0.8)))
                        .frame(
                            width: max(unit.width * geometry.size.width - 3, 2),
                            height: max(unit.height * geometry.size.height - 3, 2))
                        .offset(x: unit.minX * geometry.size.width + 1.5, y: unit.minY * geometry.size.height + 1.5)
                }
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @ObservedObject var store: SettingsStore
    @State private var restored = false

    private static let groups: [(String, [Action])] = [
        ("Focus", [.focusLeft, .focusRight, .focusUp, .focusDown, .focusFirst, .focusLast, .overview, .windowSwitcher]),
        ("Move", [.moveLeft, .moveRight, .moveUp, .moveDown, .sendToNextDisplay]),
        ("Size", [.cycleWidth, .cycleWidthBackward, .narrower, .wider, .toggleFullWidth, .center, .toggleNativeFullScreen]),
        ("Slides & columns", [.regroup, .cycleLayout, .mainLarger, .mainSmaller, .makeMain, .consumeIntoLeft, .consumeIntoRight, .expelLeft, .expel,
                              .toggleTabbed, .pinLeft, .pinRight, .toggleFloat]),
        ("Workspaces", Action.allCases.filter { $0.workspaceNumber != nil || $0.moveToWorkspaceNumber != nil }),
        ("Jump", [.focusColumn1, .focusColumn2, .focusColumn3, .focusColumn4, .focusColumn5,
                  .focusColumn6, .focusColumn7, .focusColumn8, .focusColumn9]),
        ("Snap floating windows", Action.allCases.filter { $0.snapPosition != nil } + [.snapRestore]),
        ("Marks, scratchpad & profiles", [.setMark, .jumpToMark, .lastWindow, .toggleScratchpad, .makeScratchpad,
                                          .toggleSticky, .pictureInPicture, .nextProfile]),
        ("Focus, launch & more", [.toggleFocusMode, .zoomTile, .commandPalette, .quickLaunch, .takeSnapshot]),
        ("Monorail", [.undo, .togglePause, .retile]),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Shortcut modifier keys", selection: prefix) {
                    ForEach(Keymap.prefixes, id: \.rawValue) { Text($0.symbols).tag($0) }
                }
                HStack {
                    Text("Add ⇧ to move instead of focus. Click a shortcut to change it; each action can have several.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if restored {
                        Label("Restored", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Button("Restore defaults") {
                        store.restoreDefaultShortcuts()
                        restored = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { restored = false }
                    }
                    .disabled(store.settings.keymap == .default)
                    .help(store.settings.keymap == .default ? "Your shortcuts are the defaults" : "Put every shortcut back to its default")
                }
            }
            ForEach(Self.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1, id: \.self) { action in
                        ShortcutRow(store: store, action: action)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var prefix: Binding<Modifiers> {
        Binding(
            get: { store.settings.keymap.dominantPrefix },
            set: { new in
                let old = store.settings.keymap.dominantPrefix
                store.settings.keymap = store.settings.keymap.replacingPrefix(old, with: new)
            }
        )
    }
}

private struct ShortcutRow: View {
    @ObservedObject var store: SettingsStore
    let action: Action
    @StateObject private var capture = ShortcutCapture()

    var body: some View {
        LabeledContent(action.title) {
            HStack(spacing: 6) {
                let shortcuts = store.settings.keymap.shortcuts(for: action)
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    Button {
                        record(replacing: index)
                    } label: {
                        Text(capture.recordingIndex == index ? "Type shortcut…" : shortcut.displayString)
                            .monospaced()
                    }
                    .contextMenu {
                        Button("Remove") { store.settings.keymap.unbind(action, at: index) }
                    }
                }
                if store.settings.keymap.shortcuts(for: action) != Keymap.default.shortcuts(for: action) {
                    Button {
                        capture.stop()
                        store.settings.keymap.bindings[action] = Keymap.default.shortcuts(for: action)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Back to the default for this action")
                }
                Button {
                    record(replacing: nil)
                } label: {
                    if capture.isRecording && capture.recordingIndex == nil {
                        Text("Type shortcut…")
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .help("Add a shortcut")
            }
        }
        // Restoring defaults or closing Settings ends a recording in progress.
        .onReceive(store.$cancelRecording.dropFirst()) { _ in capture.stop() }
        .onDisappear {
            if capture.isRecording {
                capture.stop()
                store.isRecordingShortcut = false
            }
        }
    }

    private func record(replacing index: Int?) {
        store.isRecordingShortcut = true
        capture.start(index: index) { shortcut in
            store.isRecordingShortcut = false
            guard let shortcut else { return }
            store.settings.keymap.bind(shortcut, to: action, replacingIndex: index)
        }
    }
}

/// Captures the next key press in the Settings window. Escape cancels.
/// Shortcuts need a modifier, except for function keys.
final class ShortcutCapture: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingIndex: Int?
    private var monitor: Any?

    func start(index: Int?, completion: @escaping (Shortcut?) -> Void) {
        stop()
        isRecording = true
        recordingIndex = index
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = Modifiers(event.modifierFlags)
            let isFunctionKey = (96...122).contains(Int(event.keyCode))
            if event.keyCode == KeyCode.escape && mods.isEmpty {
                self.stop()
                completion(nil)
            } else if mods.isEmpty && !isFunctionKey {
                NSSound.beep()  // Needs at least one modifier.
            } else {
                self.stop()
                completion(Shortcut(keyCode: event.keyCode, modifiers: mods))
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        recordingIndex = nil
    }

    deinit { stop() }
}

// MARK: - About

private struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 2) {
                Text(Brand.name).font(.largeTitle).fontWeight(.semibold)
                Text(Brand.maker).font(.title3).foregroundStyle(.secondary)
            }
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A scrolling window manager for macOS. Every window keeps its size on one endless strip.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 16) {
                Link("Website & source", destination: URL(string: "https://github.com/ashfordeOU/monorail")!)
                Link("Report an issue", destination: URL(string: "https://github.com/ashfordeOU/monorail/issues")!)
            }
            Text("\(Brand.full) · © Ashforde OÜ · Licensed under the GNU AGPL v3.0")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Reveal settings file") {
                NSWorkspace.shared.activateFileViewerSelecting([SettingsStore.fileURL])
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
#endif
