#if os(macOS)
import AppKit
import CryptoKit
import MonorailCore
import Security
import SwiftUI

/// Keeps Monorail up to date from GitHub releases: finds a newer version,
/// downloads it, checks its SHA-256 checksum and code signature, swaps it in
/// and relaunches. Checking GitHub is Monorail's only network request, and
/// it can be turned off in Settings.
final class Updater: ObservableObject {
    static let releasesURL = URL(string: "https://github.com/ashfordeOU/monorail/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/ashfordeOU/monorail/releases/latest")!
    /// With betas: the newest few releases, including pre-releases.
    private static let allReleasesURL = URL(string: "https://api.github.com/repos/ashfordeOU/monorail/releases?per_page=10")!
    /// Also offer beta (pre-release) versions.
    var betaChannel = false
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedVersion"

    struct Release {
        var version: String
        var archive: URL
        var checksums: URL
    }

    /// A newer release, once one has been found.
    @Published private(set) var available: Release?
    @Published private(set) var isInstalling = false

    /// Install without asking when a check finds a new version.
    var installAutomatically = false
    /// Called just before Monorail quits to relaunch the new version.
    var willRelaunch: () -> Void = {}

    private var timer: Timer?
    private let hud = UpdateHUD()

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Checks at most once a day while `enabled`.
    func setAutomatic(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        check(userInitiated: false)
    }

    // MARK: - Checking

    /// Looks up the latest release. User-initiated checks always report back.
    func check(userInitiated: Bool) {
        var request = URLRequest(url: betaChannel ? Self.allReleasesURL : Self.apiURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
                guard let self else { return }
                guard error == nil, let data, let release = Self.parse(data) else {
                    if userInitiated {
                        self.alert("Couldn’t check for updates", "Check your internet connection and try again.")
                    }
                    return
                }
                guard Self.isNewer(release.version, than: self.currentVersion) else {
                    self.available = nil
                    if userInitiated {
                        self.alert("Monorail is up to date", "Version \(self.currentVersion) is the latest.")
                    }
                    return
                }
                self.available = release
                let skipped = UserDefaults.standard.string(forKey: Self.skippedKey) == release.version
                if self.installAutomatically && !userInitiated {
                    self.install(release)
                } else if userInitiated || !skipped {
                    self.offer(release)
                }
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> Release? {
        let object = try? JSONSerialization.jsonObject(with: data)
        // The beta channel gets a list: take the newest that isn't a draft.
        let candidate = (object as? [[String: Any]])?.first { ($0["draft"] as? Bool) != true } ?? object as? [String: Any]
        guard let json = candidate,
            let tag = json["tag_name"] as? String,
            let assets = json["assets"] as? [[String: Any]]
        else { return nil }
        func asset(_ match: (String) -> Bool) -> URL? {
            assets.first { ($0["name"] as? String).map(match) ?? false }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }
        guard let archive = asset({ $0.hasPrefix("Monorail-") && $0.hasSuffix(".zip") })
                ?? asset({ $0.hasPrefix("MacSlider-") && $0.hasSuffix(".zip") }),
            let checksums = asset({ $0 == "SHA256SUMS" })
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, archive: archive, checksums: checksums)
    }

    /// Betas count as older than their final release (see `Version`).
    static func isNewer(_ a: String, than b: String) -> Bool {
        Version.isNewer(a, than: b)
    }

    /// Installs the release found by the last check.
    func installAvailable() {
        if let available { install(available) } else { check(userInitiated: true) }
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Monorail \(release.version) is available"
        alert.informativeText =
            "You have version \(currentVersion). Monorail can download and install it for you, then reopen with your windows where they are."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release)
        case .alertSecondButtonReturn: UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
        default: break
        }
    }

    // MARK: - Installing

    enum UpdateError: LocalizedError {
        case notWritable(String)
        case download
        case checksum
        case unpack
        case signature

        var errorDescription: String? {
            switch self {
            case .notWritable(let path): return "Monorail can’t replace itself at \(path)."
            case .download: return "The download didn’t complete."
            case .checksum: return "The download didn’t match its published checksum."
            case .unpack: return "The download couldn’t be opened."
            case .signature: return "The new version isn’t signed the same way as this one."
            }
        }
    }

    func install(_ release: Release) {
        guard !isInstalling else { return }
        let destination = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            fail(UpdateError.notWritable(destination.deletingLastPathComponent().path))
            return
        }
        isInstalling = true
        hud.show("Updating Monorail to \(release.version)…")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let app = try Self.downloadAndVerify(release)
                DispatchQueue.main.async { self.relaunch(into: app, replacing: destination) }
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.hud.hide()
                    self.fail(error)
                }
            }
        }
    }

    /// Downloads the archive and checksums, verifies both, unpacks the app
    /// and checks its signature. Runs off the main thread.
    private static func downloadAndVerify(_ release: Release) throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("Monorail-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        guard let archive = try? Data(contentsOf: release.archive),
            let sums = try? String(contentsOf: release.checksums, encoding: .utf8)
        else { throw UpdateError.download }

        let name = release.archive.lastPathComponent
        let digest = SHA256.hash(data: archive)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard let expected = checksum(for: name, in: sums), expected == actual else { throw UpdateError.checksum }

        let zip = work.appendingPathComponent(name)
        try archive.write(to: zip)
        let unpack = Process()
        unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unpack.arguments = ["-x", "-k", zip.path, work.path]
        try unpack.run()
        unpack.waitUntilExit()
        // Releases ship Monorail.app; MacSlider.app was its earlier name.
        let app = ["Monorail.app", "MacSlider.app"].map { work.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? work.appendingPathComponent("Monorail.app")
        guard unpack.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            throw UpdateError.unpack
        }
        guard signatureMatchesRunningApp(app) else { throw UpdateError.signature }
        return app
    }

    /// The checksum listed for `file` in a `shasum -a 256` output.
    private static func checksum(for file: String, in sums: String) -> String? {
        for line in sums.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if fields.count == 2, fields[1] == file { return fields[0].lowercased() }
        }
        return nil
    }

    /// The new app must carry a valid signature that satisfies this app's own
    /// designated requirement (same identifier, same certificate), so only
    /// builds signed with Monorail's certificate can replace it. A local
    /// ad-hoc build has no certificate to compare, so it only checks validity.
    private static func signatureMatchesRunningApp(_ app: URL) -> Bool {
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            return false
        }
        var requirement: SecRequirement?
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        if SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
            SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic
        {
            var designated: SecRequirement?
            if SecCodeCopyDesignatedRequirement(selfStatic, [], &designated) == errSecSuccess, let designated {
                var text: CFString?
                SecRequirementCopyString(designated, [], &text)
                // Ad-hoc requirements pin a single build's hash; nothing else can match them.
                if let text = text as String?, !text.contains("cdhash") { requirement = designated }
            }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess
    }

    /// Hands over to a small script that waits for Monorail to quit, swaps
    /// the app bundle (rolling back if that fails) and opens the new version.
    /// The new version is installed next to the running one as Monorail.app,
    /// which also renames copies installed under the old name, MacSlider.app.
    private func relaunch(into app: URL, replacing destination: URL) {
        let script = """
            pid="$1"; new="$2"; old="$3"; dest="$(dirname "$old")/Monorail.app"
            while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
            rm -rf "$old.previous"
            if mv "$old" "$old.previous" && /usr/bin/ditto "$new" "$dest"; then
                rm -rf "$old.previous"
            else
                rm -rf "$dest"; mv "$old.previous" "$old"; dest="$old"
            fi
            /usr/bin/xattr -dr com.apple.quarantine "$dest" 2>/dev/null
            rm -rf "$(dirname "$new")"
            /usr/bin/open "$dest"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c", script, "monorail-update",
            String(ProcessInfo.processInfo.processIdentifier), app.path, destination.path,
        ]
        do {
            try process.run()
        } catch {
            isInstalling = false
            hud.hide()
            fail(error)
            return
        }
        hud.show("Restarting Monorail…")
        willRelaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }

    private func fail(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Monorail couldn’t update itself"
        alert.informativeText = "\(error.localizedDescription) You can download the new version from GitHub instead."
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Self.releasesURL) }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// A small floating notice while an update downloads and installs.
private final class UpdateHUD {
    private var panel: NSPanel?
    private let model = Model()

    final class Model: ObservableObject {
        @Published var message = ""
    }

    func show(_ message: String) {
        model.message = message
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - 170, y: screen.maxY - 120))
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 64),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    private struct HUDView: View {
        @ObservedObject var model: Model

        var body: some View {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(model.message).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(width: 340, height: 64)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
#endif
