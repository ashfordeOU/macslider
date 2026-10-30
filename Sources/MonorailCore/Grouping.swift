/// Groups windows into slides by app: windows of the same app share a slide
/// (up to that app's tile count), and apps with a single window pair up with
/// each other.
public enum Grouping {
    /// Where a newly opened window should go when grouping is on.
    public enum Decision: Equatable, Sendable {
        /// Add it to the existing slide at this column index.
        case join(column: Int)
        /// Take `window` (the app's only other window, currently sharing a slide
        /// with another app) out and make a new slide with both.
        case pairWith(window: WindowID)
        /// Start a new slide.
        case newSlide
    }

    /// The complete grouping for `windows`, in order. `app` identifies each
    /// window's app; `capacity` is how many tiles a slide of that app holds.
    public static func plan(
        _ windows: [WindowID],
        app: (WindowID) -> String,
        capacity: (String) -> Int,
        pairSize: Int = 2
    ) -> [[WindowID]] {
        var order: [String] = []
        var byApp: [String: [WindowID]] = [:]
        for window in windows {
            let name = app(window)
            if byApp[name] == nil { order.append(name) }
            byApp[name, default: []].append(window)
        }

        var groups: [[WindowID]] = []
        var singles: [WindowID] = []
        // Index in `groups` reserved for the singles slide being filled.
        var singlesSlot: Int?
        for name in order {
            let members = byApp[name]!
            if members.count == 1 {
                if singlesSlot == nil {
                    singlesSlot = groups.count
                    groups.append([])
                }
                singles.append(members[0])
                groups[singlesSlot!] = singles
                if singles.count >= max(pairSize, 1) {
                    singles = []
                    singlesSlot = nil
                }
                continue
            }
            let size = min(max(capacity(name), 1), Column.maximumWindows)
            for start in stride(from: 0, to: members.count, by: size) {
                groups.append(Array(members[start..<min(start + size, members.count)]))
            }
        }
        return groups.filter { !$0.isEmpty }
    }

    /// Decides where a new window of `newApp` goes on `strip`.
    public static func decide(
        newApp: String,
        strip: Strip,
        app: (WindowID) -> String?,
        capacity: (String) -> Int,
        pairSize: Int = 2,
        pairLoneWindows: Bool = true
    ) -> Decision {
        var counts: [String: Int] = [:]
        for window in strip.allWindows {
            if let name = app(window) { counts[name, default: 0] += 1 }
        }
        // Pinned columns and columns the user arranged by hand are never touched.
        let scrolling = strip.columns.indices.filter { strip.columns[$0].pin == nil && !strip.columns[$0].isCustom }
        func apps(of column: Int) -> [String?] { strip.columns[column].windows.map(app) }

        let existing = counts[newApp] ?? 0
        if existing == 0 {
            guard pairLoneWindows else { return .newSlide }
            // A lone window: share a slide with other lone windows if one has room.
            let candidates = scrolling.filter { index in
                let column = strip.columns[index]
                return column.isTiled && column.windows.count < pairSize
                    && apps(of: index).allSatisfy { name in name.map { counts[$0] == 1 } ?? false }
            }
            if let best = nearest(candidates, to: strip.focusedColumn) { return .join(column: best) }
            return .newSlide
        }

        // Same app already on the strip: join a slide of that app with room.
        let capacityForApp = min(max(capacity(newApp), 1), Column.maximumWindows)
        let sameApp = scrolling.filter { index in
            let column = strip.columns[index]
            return column.isTiled && column.windows.count < capacityForApp
                && apps(of: index).allSatisfy { $0 == newApp }
        }
        if let best = nearest(sameApp, to: strip.focusedColumn) { return .join(column: best) }

        if existing == 1, let other = strip.allWindows.first(where: { app($0) == newApp }),
            let (column, _) = strip.locate(other), strip.columns[column].windows.count > 1,
            strip.columns[column].pin == nil, !strip.columns[column].isCustom
        {
            return .pairWith(window: other)
        }
        return .newSlide
    }

    private static func nearest(_ indices: [Int], to focus: Int) -> Int? {
        indices.min { abs($0 - focus) < abs($1 - focus) }
    }
}
