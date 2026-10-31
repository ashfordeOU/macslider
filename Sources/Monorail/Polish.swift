#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI
import UserNotifications

/// Caps Lock as the Monorail key. macOS is asked (with hidutil) to send F18
/// for Caps Lock while Monorail runs; holding it then works like ⌃⌥, and a
/// tap on its own opens the command palette. Turned back on quit.
enum CapsLockKey {
    static let f18: UInt16 = 79
    private static let capsLock = 0x7_0000_0039
    private static let f18Usage = 0x7_0000_006D

    static func set(_ on: Bool) {
        let mapping = on
            ? #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\#(capsLock),"HIDKeyboardModifierMappingDst":\#(f18Usage)}]}"#
            : #"{"UserKeyMapping":[]}"#
        // Only clear the mapping if it's ours, so other remaps survive.
        if !on, let current = run(["property", "--get", "UserKeyMapping"]),
            current.contains("HIDKeyboardModifierMappingSrc"), !current.contains(String(f18Usage))
        {
            return
        }
        _ = run(["property", "--set", mapping])
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

// MARK: - What's New

/// After an update, a window with that version's part of the changelog.
final class WhatsNew {
    private var window: NSWindow?

    func show(version: String) {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
            let changelog = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        let notes = Self.section(for: version, in: changelog)
        guard !notes.isEmpty else { return }
        let view = WhatsNewView(version: version, lines: notes) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "What’s New in \(Brand.full) \(version)"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The lines between "## [version]" and the next "## [".
    static func section(for version: String, in changelog: String) -> [String] {
        var lines: [String] = []
        var inside = false
        for line in changelog.components(separatedBy: .newlines) {
            if line.hasPrefix("## [") {
                if inside { break }
                inside = line.hasPrefix("## [\(version)]")
                continue
            }
            if inside, !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
        }
        return lines
    }
}

private struct WhatsNewView: View {
    let version: String
    let lines: [String]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What’s new in \(version)").font(.title2).fontWeight(.semibold)
                    Text(Brand.full).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("### ") {
                            Text(line.dropFirst(4)).font(.headline).padding(.top, 6)
                        } else {
                            let text = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 360)
            HStack {
                Link("Full changelog", destination: URL(string: "https://github.com/ashfordeOU/monorail/blob/main/CHANGELOG.md")!)
                Spacer()
                Button("Continue", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

// MARK: - Weekly summary

/// Monday mornings: a notification with last week's switches, top workspace and top pair.
final class WeeklySummary {
    var stats: UsageStats?
    var workspaceTitle: (Int) -> String = { _ in "" }
    var isEnabled: () -> Bool = { false }
    private var timer: Timer?
    private static let sentKey = "weeklySummarySent"

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.check() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.check() }
    }

    private func check() {
        guard isEnabled(), let stats else { return }
        let calendar = Calendar.current
        let now = Date()
        guard calendar.component(.weekday, from: now) == 2, calendar.component(.hour, from: now) >= 9 else { return }
        let week = "\(calendar.component(.yearForWeekOfYear, from: now))-\(calendar.component(.weekOfYear, from: now))"
        guard UserDefaults.standard.string(forKey: Self.sentKey) != week else { return }
        let days = stats.lastDays(8).dropLast()
        let switches = days.reduce(0) { $0 + $1.day.switches }
        guard switches > 0 else { return }
        let time = stats.time(days: 7)
        var body = "\(switches) slide switches"
        if let top = time.workspaces.first { body += " · most time in \(top.0) (\(InsightsPane.duration(top.1)))" }
        if let pair = stats.topPairs(1).first {
            body += " · \(pair.apps.map(UsageStats.appName).joined(separator: " + ")) together most"
        }
        let content = UNMutableNotificationContent()
        content.title = "Your week with Monorail"
        content.body = body
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: "weekly-\(week)", content: content, trigger: nil))
            DispatchQueue.main.async { UserDefaults.standard.set(week, forKey: Self.sentKey) }
        }
    }
}
#endif
