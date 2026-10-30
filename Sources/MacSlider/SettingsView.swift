#if os(macOS)
import AppKit
import MacSliderCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, layout, input, appearance, apps, shortcuts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .input: return "Motion & Input"
        case .appearance: return "Appearance"
        case .apps: return "Apps"
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
            ShortcutsPane(store: store)
                .tabItem { Label(SettingsTab.shortcuts.title, systemImage: SettingsTab.shortcuts.symbol) }
                .tag(SettingsTab.shortcuts)
            AboutPane()
                .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.symbol) }
                .tag(SettingsTab.about)
        }
        .frame(width: 720, height: 620)
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
                Toggle("Launch MacSlider at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LoginItem.setEnabled($0) }
                Toggle("Pause tiling", isOn: $paused)
                    .onChange(of: paused) { setPaused($0) }
                Toggle("Show column position in the menu bar", isOn: $store.settings.showColumnIndicator)
                Stepper(value: $store.settings.workspaceCount, in: 1...9) {
                    Text("Workspaces per display: \(store.settings.workspaceCount)")
                }
                Toggle("Check for updates automatically", isOn: $store.settings.checkForUpdates)
                Picker("New windows open", selection: $store.settings.newWindowPosition) {
                    Text("Next to the focused window").tag(Strip.InsertPosition.afterFocused)
                    Text("At the end of the strip").tag(Strip.InsertPosition.end)
                    Text("At the start of the strip").tag(Strip.InsertPosition.start)
                }
            }
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
                Toggle("Group windows into slides by app", isOn: $store.settings.groupByApp)
                Stepper(value: $store.settings.tilesPerSlide, in: 1...4) {
                    Text("Windows per slide: \(store.settings.tilesPerSlide)")
                }
                .disabled(!store.settings.groupByApp)
            } header: {
                Text("Slides")
            } footer: {
                Text("Windows of the same app share a full-screen slide; apps with one window pair up with another. Terminals get four tiles per slide — change this per app under Apps. Press ⌃⌥A to regroup everything, ⌃⌥G to turn any column into a grid.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Spacing") {
                LabeledSlider(title: "Gap between windows", value: $store.settings.layout.gap, range: 0...40)
                LabeledSlider(title: "Gap at screen edges", value: $store.settings.layout.edgeGap, range: 0...40)
            }
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

    var body: some View {
        Form {
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
                            Text(rule.bundleID).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                store.settings.appRules.removeAll { $0.bundleID == rule.bundleID }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack(spacing: 16) {
                            Toggle("Float", isOn: $rule.float)
                            Picker("Width", selection: $rule.width) {
                                Text("Default").tag(Double?.none)
                                ForEach(widthChoices, id: \.1) { Text($0.0).tag(Double?.some($0.1)) }
                            }
                            .frame(width: 150)
                            .disabled(rule.float)
                            Picker("Per slide", selection: $rule.tiles) {
                                Text("Default").tag(Int?.none)
                                ForEach(1...4, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                            }
                            .frame(width: 130)
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
                    }
                    .padding(.vertical, 2)
                }
                Menu("Add a running app…") {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            store.settings.appRules.append(
                                AppRule(bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!))
                        }
                    }
                }
            } header: {
                Text("Per-app rules")
            } footer: {
                Text("Floating apps stay where you put them. Dialogs, panels and fixed-size windows always float. Rules apply to windows opened after the change; press ⌃⌥T to float or tile a window right now.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @ObservedObject var store: SettingsStore

    private static let groups: [(String, [Action])] = [
        ("Focus", [.focusLeft, .focusRight, .focusUp, .focusDown, .focusFirst, .focusLast, .overview, .windowSwitcher]),
        ("Move", [.moveLeft, .moveRight, .moveUp, .moveDown, .sendToNextDisplay]),
        ("Size", [.cycleWidth, .cycleWidthBackward, .narrower, .wider, .toggleFullWidth, .center, .toggleNativeFullScreen]),
        ("Slides & columns", [.regroup, .toggleGrid, .consumeIntoLeft, .consumeIntoRight, .expelLeft, .expel,
                              .toggleTabbed, .pinLeft, .pinRight, .toggleFloat]),
        ("Workspaces", Action.allCases.filter { $0.workspaceNumber != nil || $0.moveToWorkspaceNumber != nil }),
        ("Jump", [.focusColumn1, .focusColumn2, .focusColumn3, .focusColumn4, .focusColumn5,
                  .focusColumn6, .focusColumn7, .focusColumn8, .focusColumn9]),
        ("MacSlider", [.togglePause, .retile]),
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
                    Button("Restore defaults") { store.settings.keymap = .default }
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
            Text("MacSlider").font(.largeTitle).fontWeight(.semibold)
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A scrolling window manager for macOS. Every window keeps its size on one endless strip.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 16) {
                Link("Website & source", destination: URL(string: "https://github.com/ashfordeOU/macslider")!)
                Link("Report an issue", destination: URL(string: "https://github.com/ashfordeOU/macslider/issues")!)
            }
            Text("© Ashforde OÜ · Licensed under the GNU AGPL v3.0")
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
