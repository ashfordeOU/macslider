#if os(macOS)
import AppKit

/// Looks for a newer release on GitHub. This is MacSlider's only network
/// request, and it can be turned off in Settings.
final class Updater {
    static let releasesURL = URL(string: "https://github.com/ashfordeOU/macslider/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/ashfordeOU/macslider/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedVersion"

    private var timer: Timer?

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

    /// Fetches the latest release. User-initiated checks always report back.
    func check(userInitiated: Bool) {
        var request = URLRequest(url: Self.apiURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
                guard let self else { return }
                guard error == nil, let data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let tag = json["tag_name"] as? String
                else {
                    if userInitiated { self.alert("Couldn’t check for updates", "Check your internet connection and try again.") }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let skipped = UserDefaults.standard.string(forKey: Self.skippedKey)
                if Self.isNewer(latest, than: self.currentVersion) {
                    if userInitiated || skipped != latest { self.offer(latest) }
                } else if userInitiated {
                    self.alert("MacSlider is up to date", "Version \(self.currentVersion) is the latest.")
                }
            }
        }.resume()
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

    private func offer(_ version: String) {
        let alert = NSAlert()
        alert.messageText = "MacSlider \(version) is available"
        alert.informativeText = "You have version \(currentVersion). Download the new version from GitHub?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(Self.releasesURL)
        case .alertSecondButtonReturn: UserDefaults.standard.set(version, forKey: Self.skippedKey)
        default: break
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
#endif
