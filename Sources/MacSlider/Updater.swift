#if os(macOS)
import AppKit
import CryptoKit
import Security
import SwiftUI

/// Keeps MacSlider up to date from GitHub releases: finds a newer version,
/// downloads it, checks its SHA-256 checksum and code signature, swaps it in
/// and relaunches. Checking GitHub is MacSlider's only network request, and
/// it can be turned off in Settings.
final class Updater: ObservableObject {
    static let releasesURL = URL(string: "https://github.com/ashfordeOU/macslider/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/ashfordeOU/macslider/releases/latest")!
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
    /// Called just before MacSlider quits to relaunch the new version.
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
        var request = URLRequest(url: Self.apiURL, timeoutInterval: 15)
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
                        self.alert("MacSlider is up to date", "Version \(self.currentVersion) is the latest.")
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
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String,
            let assets = json["assets"] as? [[String: Any]]
        else { return nil }
        func asset(_ match: (String) -> Bool) -> URL? {
            assets.first { ($0["name"] as? String).map(match) ?? false }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }
        guard let archive = asset({ $0.hasPrefix("MacSlider-") && $0.hasSuffix(".zip") }),
            let checksums = asset({ $0 == "SHA256SUMS" })
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, archive: archive, checksums: checksums)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let x = i < lhs.count ? lhs[i] : 0
            let y = i < rhs.count ? rhs[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Installs the release found by the last check.
    func installAvailable() {
        if let available { install(available) } else { check(userInitiated: true) }
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "MacSlider \(release.version) is available"
        alert.informativeText =
            "You have version \(currentVersion). MacSlider can download and install it for you, then reopen with your windows where they are."
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
            case .notWritable(let path): return "MacSlider can’t replace itself at \(path)."
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
        hud.show("Updating MacSlider to \(release.version)…")
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
            .appendingPathComponent("MacSlider-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        guard let archive = try? Data(contentsOf: release.archive),
            let sums = try? String(contentsOf: release.checksums, encoding: .utf8)
        else { throw UpdateError.download }

        let name = release.archive.lastPathComponent
        let expected = sums.split(separator: "\n")
            .map { $0.split(separator: " ", omittingEmptySubsequences: true) }
            .first { $0.count == 2 && $0[1] == Substring(name) }?[0]
        let actual = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard let expected, expected.lowercased() == actual else { throw UpdateError.checksum }

        let zip = work.appendingPathComponent(name)
        try archive.write(to: zip)
        let unpack = Process()
        unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unpack.arguments = ["-x", "-k", zip.path, work.path]
        try unpack.run()
        unpack.waitUntilExit()
        let app = work.appendingPathComponent("MacSlider.app")
        guard unpack.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            throw UpdateError.unpack
        }
        guard signatureMatchesRunningApp(app) else { throw UpdateError.signature }
        return app
    }

    /// The new app must carry a valid signature that satisfies this app's own
    /// designated requirement (same identifier, same certificate), so only
    /// builds signed with MacSlider's certificate can replace it. A local
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

    /// Hands over to a small script that waits for MacSlider to quit, swaps
    /// the app bundle (rolling back if that fails) and opens the new version.
    private func relaunch(into app: URL, replacing destination: URL) {
        let script = """
            pid="$1"; new="$2"; dest="$3"
            while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
            rm -rf "$dest.previous"
            if mv "$dest" "$dest.previous" && /usr/bin/ditto "$new" "$dest"; then
                rm -rf "$dest.previous"
            else
                rm -rf "$dest"; mv "$dest.previous" "$dest"
            fi
            /usr/bin/xattr -dr com.apple.quarantine "$dest" 2>/dev/null
            rm -rf "$(dirname "$new")"
            /usr/bin/open "$dest"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c", script, "macslider-update",
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
        hud.show("Restarting MacSlider…")
        willRelaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }

    private func fail(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "MacSlider couldn’t update itself"
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
