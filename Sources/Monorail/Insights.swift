#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

/// Things the engine reports for Insights.
enum UsageEvent {
    case switched, windowOpened, focusSession
}

/// Counts kept on this Mac only: how you move around, and which apps you
/// keep side by side, to suggest app pairs. Nothing leaves the Mac.
final class UsageStats: ObservableObject {
    struct Day: Codable, Equatable {
        var switches = 0
        var windowsOpened = 0
        var focusSessions = 0
        var mostSlides = 0
        /// Minutes spent in each workspace (by name) and each app.
        var workspaceMinutes: [String: Int] = [:]
        var appMinutes: [String: Int] = [:]

        init() {}

        // Days saved before time was counted have no minutes.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switches = try c.decodeIfPresent(Int.self, forKey: .switches) ?? 0
            windowsOpened = try c.decodeIfPresent(Int.self, forKey: .windowsOpened) ?? 0
            focusSessions = try c.decodeIfPresent(Int.self, forKey: .focusSessions) ?? 0
            mostSlides = try c.decodeIfPresent(Int.self, forKey: .mostSlides) ?? 0
            workspaceMinutes = try c.decodeIfPresent([String: Int].self, forKey: .workspaceMinutes) ?? [:]
            appMinutes = try c.decodeIfPresent([String: Int].self, forKey: .appMinutes) ?? [:]
        }
    }

    private struct Stored: Codable {
        var days: [String: Day] = [:]
        /// Minutes each pair of apps (bundle IDs joined by "|") spent in one slide.
        var pairMinutes: [String: Int] = [:]
        var dismissed: [String] = []
        var announced: [String] = []
    }

    @Published private var stored = Stored()
    var isEnabled = true
    /// Called once when a pair becomes worth suggesting.
    var onSuggestion: (String) -> Void = { _ in }

    /// Minutes together before a pair is suggested.
    static let suggestAfter = 45

    private static var url: URL { SettingsStore.directory.appendingPathComponent("insights.json") }
    private var saveTimer: Timer?

    init() {
        if let data = try? Data(contentsOf: Self.url), let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        }
    }

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func dayKey(_ date: Date = Date()) -> String { dayFormat.string(from: date) }

    func record(_ event: UsageEvent) {
        guard isEnabled else { return }
        let key = Self.dayKey()
        var day = stored.days[key] ?? Day()
        switch event {
        case .switched: day.switches += 1
        case .windowOpened: day.windowsOpened += 1
        case .focusSession: day.focusSessions += 1
        }
        stored.days[key] = day
        scheduleSave()
    }

    /// Called once a minute with the apps sharing each visible slide.
    func sample(slides: [[String]], slideCount: Int) {
        guard isEnabled else { return }
        let key = Self.dayKey()
        var day = stored.days[key] ?? Day()
        day.mostSlides = max(day.mostSlides, slideCount)
        stored.days[key] = day
        for apps in slides {
            for (i, a) in apps.enumerated() {
                for b in apps[(i + 1)...] {
                    let pair = "\(a)|\(b)"
                    stored.pairMinutes[pair, default: 0] += 1
                    if stored.pairMinutes[pair] == Self.suggestAfter, !stored.announced.contains(pair),
                        !stored.dismissed.contains(pair)
                    {
                        stored.announced.append(pair)
                        onSuggestion(pair)
                    }
                }
            }
        }
        // Keep two months.
        if let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) {
            let oldest = Self.dayKey(cutoff)
            stored.days = stored.days.filter { $0.key >= oldest }
        }
        scheduleSave()
    }

    /// One more minute in this workspace and app (called once a minute).
    func addMinute(workspace: String, app: String?) {
        guard isEnabled else { return }
        let key = Self.dayKey()
        var day = stored.days[key] ?? Day()
        day.workspaceMinutes[workspace, default: 0] += 1
        if let app { day.appMinutes[app, default: 0] += 1 }
        stored.days[key] = day
        scheduleSave()
    }

    /// Minutes per workspace and per app over the last `days` days, most first.
    func time(days: Int) -> (workspaces: [(String, Int)], apps: [(String, Int)]) {
        var workspaces: [String: Int] = [:]
        var apps: [String: Int] = [:]
        for (_, day) in lastDays(days) {
            workspaces.merge(day.workspaceMinutes, uniquingKeysWith: +)
            apps.merge(day.appMinutes, uniquingKeysWith: +)
        }
        return (workspaces.sorted { $0.value > $1.value }.map { ($0.key, $0.value) },
                apps.sorted { $0.value > $1.value }.map { ($0.key, $0.value) })
    }

    var today: Day { stored.days[Self.dayKey()] ?? Day() }

    /// The last `count` days, oldest first.
    func lastDays(_ count: Int) -> [(label: String, day: Day)] {
        let labels = DateFormatter()
        labels.dateFormat = "EEE"
        return (0..<count).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return (labels.string(from: date), stored.days[Self.dayKey(date)] ?? Day())
        }
    }

    /// Pairs used together most, as bundle IDs with minutes.
    func topPairs(_ count: Int = 5) -> [(apps: [String], minutes: Int)] {
        stored.pairMinutes.sorted { $0.value > $1.value }.prefix(count).map {
            ($0.key.split(separator: "|").map(String.init), $0.value)
        }
    }

    /// Pairs worth saving: used together a while, not saved or dismissed.
    func suggestions(excluding pairs: [AppPair]) -> [[String]] {
        let saved = Set(pairs.map { Set($0.bundleIDs) })
        return topPairs(10).filter { pair in
            pair.minutes >= Self.suggestAfter && !saved.contains(Set(pair.apps))
                && !stored.dismissed.contains(pair.apps.joined(separator: "|"))
        }.map(\.apps)
    }

    func dismiss(_ apps: [String]) {
        stored.dismissed.append(apps.joined(separator: "|"))
        scheduleSave()
    }

    func reset() {
        stored = Stored()
        save()
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.save() }
    }

    func save() {
        try? FileManager.default.createDirectory(at: SettingsStore.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(stored).write(to: Self.url, options: .atomic)
    }

    static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
    }
}

/// Where the time went, today and over the week.
private struct TimeSection: View {
    @ObservedObject var stats: UsageStats
    @State private var week = false

    var body: some View {
        let time = stats.time(days: week ? 7 : 1)
        let total = max(time.workspaces.map(\.1).reduce(0, +), 1)
        Section {
            Picker("", selection: $week) {
                Text("Today").tag(false)
                Text("This week").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if time.workspaces.isEmpty {
                Text("Nothing counted yet. Time is noted once a minute while you work.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(time.workspaces.prefix(6).enumerated()), id: \.offset) { _, entry in
                HStack {
                    Text(entry.0).frame(width: 160, alignment: .leading)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.7))
                            .frame(width: max(3, geometry.size.width * CGFloat(entry.1) / CGFloat(total)))
                    }
                    .frame(height: 10)
                    Text(InsightsPane.duration(entry.1)).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                }
            }
            if !time.apps.isEmpty {
                Text("Most-used apps: " + time.apps.prefix(5).map { "\($0.0) \(InsightsPane.duration($0.1))" }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("Where the time went")
        }
    }
}

/// Settings → Insights.
struct InsightsPane: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var stats: UsageStats

    var body: some View {
        Form {
            Section {
                Toggle("Count switches and pairings on this Mac", isOn: $store.settings.collectStats)
                if store.settings.collectStats {
                    HStack(spacing: 24) {
                        figure("\(stats.today.switches)", "slide switches today")
                        figure("\(stats.today.windowsOpened)", "windows opened")
                        figure("\(stats.today.mostSlides)", "slides at most")
                        figure("\(stats.today.focusSessions)", "focus sessions")
                    }
                    .padding(.vertical, 4)
                    week
                }
            } header: {
                Text("Today")
            } footer: {
                Text("Stays on this Mac. Nothing is sent anywhere.").font(.callout).foregroundStyle(.secondary)
            }
            if store.settings.collectStats {
                TimeSection(stats: stats)
                Section("Suggested app pairs") {
                    let suggestions = stats.suggestions(excluding: store.settings.appPairs)
                    if suggestions.isEmpty {
                        Text("Nothing yet. When you keep two apps side by side for a while, Monorail suggests saving them as an app pair.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(suggestions, id: \.self) { apps in
                        HStack {
                            Text(apps.map(UsageStats.appName).joined(separator: " + "))
                            Spacer()
                            Button("Save as App Pair") {
                                store.settings.appPairs.append(AppPair(
                                    name: apps.map(UsageStats.appName).joined(separator: " + "), bundleIDs: apps,
                                    arrangement: .columns))
                            }
                            Button("Dismiss") { stats.dismiss(apps) }.buttonStyle(.borderless)
                        }
                    }
                }
                Section("Apps you pair most") {
                    let top = stats.topPairs()
                    if top.isEmpty { Text("No pairs yet.").foregroundStyle(.secondary) }
                    ForEach(Array(top.enumerated()), id: \.offset) { _, pair in
                        LabeledContent(pair.apps.map(UsageStats.appName).joined(separator: " + ")) {
                            Text(Self.duration(pair.minutes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Button("Reset Insights", role: .destructive) { stats.reset() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Switches over the last seven days.
    private var week: some View {
        let days = stats.lastDays(7)
        let most = max(days.map(\.day.switches).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, entry in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == days.count - 1 ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .frame(width: 26, height: max(3, 60 * CGFloat(entry.day.switches) / CGFloat(most)))
                        .help("\(entry.day.switches) switches")
                    Text(entry.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 80, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide switches over the last seven days: "
            + days.map { "\($0.label) \($0.day.switches)" }.joined(separator: ", "))
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%.1f h", Double(minutes) / 60)
    }
}
#endif
