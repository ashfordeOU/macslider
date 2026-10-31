#if os(macOS)
import AppKit
import MonorailCore

/// Lets other tools follow Monorail: a state file and a notification for
/// status bars like SketchyBar, a script run on events, and a desktop picture
/// per workspace.
final class Integrations {
    /// What other tools can read from state.json.
    struct State: Codable, Equatable {
        var workspace: Int
        var workspaceName: String
        var workspaceCount: Int
        var profile: String
        var slide: Int
        var slides: Int
        var app: String?
        var title: String?
        var focusMode: Bool
    }

    static var stateURL: URL { SettingsStore.directory.appendingPathComponent("state.json") }
    /// Posted (distributed) whenever the state changes.
    static let notification = Notification.Name("org.ashforde.monorail.changed")

    private var last: State?
    private var lastWallpaper: [String: String] = [:]
    private var pending: Timer?

    /// Called on every state change; coalesced so bursts cost one write.
    func update(_ state: @escaping () -> State?, settings: AppSettings) {
        pending?.invalidate()
        pending = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self, let state = state() else { return }
            self.publish(state, settings: settings)
        }
    }

    private func publish(_ state: State, settings: AppSettings) {
        let previous = last
        guard state != previous else { return }
        last = state
        if settings.publishState {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(state).write(to: Self.stateURL, options: .atomic)
            DistributedNotificationCenter.default().postNotificationName(
                Self.notification, object: nil, userInfo: nil, deliverImmediately: true)
        }
        if previous?.workspace != state.workspace || previous?.profile != state.profile {
            setWallpaper(for: state.workspace - 1, settings: settings)
            run(settings.eventScript, event: "workspace_changed", state: state)
        }
        if previous?.app != state.app || previous?.title != state.title {
            run(settings.eventScript, event: "focus_changed", state: state)
        }
        if previous?.focusMode != state.focusMode {
            run(settings.eventScript, event: state.focusMode ? "focus_mode_on" : "focus_mode_off", state: state)
        }
    }

    /// Runs the user's script with the event and state in environment variables.
    private func run(_ script: String, event: String, state: State) {
        let path = (script as NSString).expandingTildeInPath
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [event]
        var environment = ProcessInfo.processInfo.environment
        environment["MONORAIL_EVENT"] = event
        environment["MONORAIL_WORKSPACE"] = String(state.workspace)
        environment["MONORAIL_WORKSPACE_NAME"] = state.workspaceName
        environment["MONORAIL_PROFILE"] = state.profile
        environment["MONORAIL_SLIDE"] = String(state.slide)
        environment["MONORAIL_SLIDES"] = String(state.slides)
        environment["MONORAIL_APP"] = state.app ?? ""
        environment["MONORAIL_TITLE"] = state.title ?? ""
        environment["MONORAIL_FOCUS_MODE"] = state.focusMode ? "1" : "0"
        process.environment = environment
        do {
            try process.run()
        } catch {
            log.error("Event script failed: \(error.localizedDescription)")
        }
    }

    /// A desktop picture per workspace: set on every screen when it changes.
    private func setWallpaper(for workspace: Int, settings: AppSettings) {
        guard let path = settings.workspaceWallpapers[String(workspace)], !path.isEmpty,
            FileManager.default.fileExists(atPath: path)
        else { return }
        let url = URL(fileURLWithPath: path)
        for screen in NSScreen.screens {
            let key = screen.localizedName
            guard lastWallpaper[key] != path else { continue }
            if (try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])) != nil {
                lastWallpaper[key] = path
            }
        }
    }
}
#endif
