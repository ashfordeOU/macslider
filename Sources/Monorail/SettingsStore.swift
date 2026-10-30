#if os(macOS)
import AppKit
import Combine
import MonorailCore
import ServiceManagement

/// Loads and saves `Settings`, and publishes changes to the UI and engine.
/// Changes apply immediately; there is no Save button.
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            onChange(settings)
        }
    }

    /// True while the Settings window is capturing a new shortcut.
    @Published var isRecordingShortcut = false {
        didSet { onRecordingChange(isRecordingShortcut) }
    }

    var onChange: (AppSettings) -> Void = { _ in }
    var onRecordingChange: (Bool) -> Void = { _ in }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Monorail", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("settings.json") }

    /// Monorail was called MacSlider; move its settings folder over once.
    private static func migrateFromOldName() {
        let old = directory.deletingLastPathComponent().appendingPathComponent("MacSlider", isDirectory: true)
        let manager = FileManager.default
        guard manager.fileExists(atPath: old.path), !manager.fileExists(atPath: directory.path) else { return }
        try? manager.moveItem(at: old, to: directory)
    }

    init() {
        Self.migrateFromOldName()
        if let data = try? Data(contentsOf: Self.fileURL),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: Self.fileURL, options: .atomic)
        } catch {
            log.error("Saving settings failed: \(error.localizedDescription)")
        }
        if settings.syncThroughICloud { scheduleCloudPush() }
    }

    // MARK: - Export, import and iCloud Drive

    /// Everything worth moving to another Mac: settings (with app pairs,
    /// custom layouts, rules and shortcuts) and saved layouts.
    struct SettingsBundle: Codable {
        var settings: AppSettings
        var layouts: [SavedLayout]?
        var savedAt: Date
        var machine: String
    }

    static var layoutsURL: URL { directory.appendingPathComponent("saved-layouts.json") }
    /// Called after import or sync replaced the saved layouts on disk.
    var onLayoutsChanged: () -> Void = {}

    private static var machine: String { Host.current().localizedName ?? "Mac" }

    func makeBundle() -> SettingsBundle {
        let layouts = (try? Data(contentsOf: Self.layoutsURL)).flatMap { try? JSONDecoder().decode([SavedLayout].self, from: $0) }
        return SettingsBundle(settings: settings, layouts: layouts, savedAt: Date(), machine: Self.machine)
    }

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(makeBundle()).write(to: url, options: .atomic)
    }

    func importBundle(from url: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        apply(try decoder.decode(SettingsBundle.self, from: Data(contentsOf: url)), keepSync: true)
    }

    /// Takes settings from another Mac, keeping this Mac's own choices about
    /// syncing and its displays.
    private func apply(_ bundle: SettingsBundle, keepSync: Bool) {
        var incoming = bundle.settings
        if keepSync { incoming.syncThroughICloud = settings.syncThroughICloud }
        incoming.displayOverrides.merge(settings.displayOverrides) { _, mine in mine }
        incoming.hasCompletedOnboarding = settings.hasCompletedOnboarding
        if let layouts = bundle.layouts, let data = try? JSONEncoder().encode(layouts) {
            try? data.write(to: Self.layoutsURL, options: .atomic)
            onLayoutsChanged()
        }
        settings = incoming
    }

    /// iCloud Drive's Monorail folder, if iCloud Drive is on.
    static var cloudURL: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Monorail/monorail-settings.json")
    }

    private var cloudPushTimer: Timer?
    private var cloudPullTimer: Timer?
    private var lastCloudSync = Date.distantPast

    private func scheduleCloudPush() {
        cloudPushTimer?.invalidate()
        cloudPushTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.pushToCloud() }
    }

    func pushToCloud() {
        guard settings.syncThroughICloud, let url = Self.cloudURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bundle = makeBundle()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(bundle), (try? data.write(to: url, options: .atomic)) != nil {
            lastCloudSync = bundle.savedAt
        }
    }

    /// Picks up changes another Mac saved to iCloud Drive.
    func pullFromCloud() {
        guard settings.syncThroughICloud, let url = Self.cloudURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(SettingsBundle.self, from: data), bundle.machine != Self.machine,
            bundle.savedAt > lastCloudSync
        else { return }
        lastCloudSync = bundle.savedAt
        apply(bundle, keepSync: true)
    }

    /// Checks iCloud Drive now and every minute while syncing is on.
    func startCloudSync() {
        cloudPullTimer?.invalidate()
        cloudPullTimer = nil
        guard settings.syncThroughICloud else { return }
        pullFromCloud()
        pushToCloud()
        cloudPullTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.pullFromCloud() }
    }
}

/// Launch at login through `SMAppService` (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Launch at login change failed: \(error.localizedDescription)")
        }
    }
}

/// Mac setup checks shown in Settings and the welcome window.
struct SetupCheck: Identifiable {
    enum State { case ok, warning }

    var id: String
    var title: String
    var detail: String
    var state: State
    var fixURL: URL?

    static func run(settings: AppSettings) -> [SetupCheck] {
        var checks: [SetupCheck] = []
        let accessibilityURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

        let trusted = Accessibility.isTrusted(prompt: false)
        checks.append(
            SetupCheck(
                id: "accessibility",
                title: "Accessibility permission",
                detail: trusted
                    ? "Granted. Monorail can arrange windows."
                    : "Required to move and resize windows. Turn Monorail on in Privacy & Security → Accessibility.",
                state: trusted ? .ok : .warning,
                fixURL: trusted ? nil : accessibilityURL
            ))

        let conflicting: [String: String] = [
            "com.knollsoft.Rectangle": "Rectangle",
            "com.knollsoft.Hookshot": "Hookshot",
            "com.crowdcafe.windowmagnet": "Magnet",
            "com.amethyst.Amethyst": "Amethyst",
            "bobko.aerospace": "AeroSpace",
            "com.koekeishiya.yabai": "yabai",
            "com.hegenberg.BetterTouchTool": "BetterTouchTool",
            "com.manytricks.Moom": "Moom",
            "com.sadopc.Spectacle": "Spectacle",
        ]
        let running = NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.flatMap { conflicting[$0] }
        }
        checks.append(
            SetupCheck(
                id: "conflicts",
                title: "Other window managers",
                detail: running.isEmpty
                    ? "None running."
                    : "\(running.joined(separator: ", ")) may move windows too. Quit it or turn off its window snapping.",
                state: running.isEmpty ? .ok : .warning
            ))

        let stageManager = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        checks.append(
            SetupCheck(
                id: "stage-manager",
                title: "Stage Manager",
                detail: stageManager
                    ? "Stage Manager is on and rearranges windows. Turn it off in Control Centre."
                    : "Off.",
                state: stageManager ? .warning : .ok,
                fixURL: stageManager ? URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") : nil
            ))

        if NSScreen.screens.count > 1 {
            let separate = !(UserDefaults(suiteName: "com.apple.spaces")?.bool(forKey: "spans-displays") ?? false)
            checks.append(
                SetupCheck(
                    id: "spaces",
                    title: "Displays have separate Spaces",
                    detail: separate
                        ? "On. Each display scrolls on its own."
                        : "Off. Turn on “Displays have separate Spaces” in Desktop & Dock for one strip per display.",
                    state: separate ? .ok : .warning,
                    fixURL: separate ? nil : URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
                ))
        }

        if settings.swipeFingers != .off {
            let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
            let key = settings.swipeFingers == .three
                ? "TrackpadThreeFingerHorizSwipeGesture" : "TrackpadFourFingerHorizSwipeGesture"
            let conflict = domains.contains { (UserDefaults(suiteName: $0)?.integer(forKey: key) ?? 0) != 0 }
            let fingers = settings.swipeFingers == .three ? "three" : "four"
            checks.append(
                SetupCheck(
                    id: "trackpad",
                    title: "Trackpad swipe",
                    detail: conflict
                        ? "macOS also uses \(fingers)-finger horizontal swipes to switch Spaces. Set “Swipe between full-screen applications” to a different finger count in Trackpad → More Gestures."
                        : "No conflict with macOS gestures.",
                    state: conflict ? .warning : .ok,
                    fixURL: conflict ? URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") : nil
                ))
        }
        return checks
    }
}
#endif
