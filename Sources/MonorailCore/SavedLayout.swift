/// Identifies a window across restarts, when its `WindowID` changes: the app
/// it belongs to and its title.
public struct WindowFingerprint: Hashable, Codable, Sendable {
    public var app: String
    public var title: String

    public init(app: String, title: String) {
        self.app = app
        self.title = title
    }
}

/// One slide of a saved layout, described by the windows' fingerprints.
public struct SavedColumn: Equatable, Codable, Sendable {
    public var windows: [WindowFingerprint]
    public var width: Double
    public var arrangement: Arrangement
    public var split: Double
    public var isTabbed: Bool
    public var pin: PinSide?

    public init(_ column: Column, fingerprint: (WindowID) -> WindowFingerprint?) {
        windows = column.windows.compactMap(fingerprint)
        width = column.width
        arrangement = column.arrangement
        split = column.split
        isTabbed = column.isTabbed
        pin = column.pin
    }
}

/// A named arrangement of slides for each workspace, to bring back later.
public struct SavedLayout: Equatable, Codable, Sendable, Identifiable {
    public var name: String
    /// Saved columns per workspace index.
    public var workspaces: [Int: [SavedColumn]]

    public var id: String { name }

    public init(name: String, workspaces: [Int: [SavedColumn]]) {
        self.name = name
        self.workspaces = workspaces
    }

    public var windowCount: Int { workspaces.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.windows.count } } }
}

public enum LayoutMatcher {
    /// Turns saved columns back into columns of real windows. Each saved
    /// fingerprint takes the open window with the same app and title; any left
    /// over then take an unused window of the same app. Windows in `used` are
    /// skipped and the ones taken are added to it. Empty columns are dropped.
    public static func columns(
        for saved: [SavedColumn],
        windows: [(id: WindowID, fingerprint: WindowFingerprint)],
        used: inout Set<WindowID>
    ) -> [Column] {
        var assigned: [[WindowID?]] = saved.map { Array(repeating: nil, count: $0.windows.count) }
        // Pass 1: exact app and title.
        for (c, column) in saved.enumerated() {
            for (r, print) in column.windows.enumerated() {
                if let match = windows.first(where: { !used.contains($0.id) && $0.fingerprint == print }) {
                    assigned[c][r] = match.id
                    used.insert(match.id)
                }
            }
        }
        // Pass 2: same app, any title (titles change as you browse or edit).
        for (c, column) in saved.enumerated() {
            for (r, print) in column.windows.enumerated() where assigned[c][r] == nil {
                if let match = windows.first(where: { !used.contains($0.id) && $0.fingerprint.app == print.app }) {
                    assigned[c][r] = match.id
                    used.insert(match.id)
                }
            }
        }
        return saved.enumerated().compactMap { c, column in
            let ids = assigned[c].compactMap { $0 }
            guard !ids.isEmpty else { return nil }
            return Column(
                windows: ids, width: column.width, isTabbed: column.isTabbed,
                arrangement: column.arrangement, split: column.split, pin: column.pin, isCustom: true)
        }
    }
}

/// Where Magnet-style snapping puts a floating window, as a unit rectangle
/// of the display's visible area.
public enum SnapPosition: String, Codable, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center

    public var unit: Rect {
        let third = 1.0 / 3.0
        switch self {
        case .leftHalf: return Rect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return Rect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return Rect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return Rect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .firstThird: return Rect(x: 0, y: 0, width: third, height: 1)
        case .centerThird: return Rect(x: third, y: 0, width: third, height: 1)
        case .lastThird: return Rect(x: 2 * third, y: 0, width: third, height: 1)
        case .firstTwoThirds: return Rect(x: 0, y: 0, width: 2 * third, height: 1)
        case .lastTwoThirds: return Rect(x: third, y: 0, width: 2 * third, height: 1)
        case .topLeft: return Rect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return Rect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return Rect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return Rect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .maximize: return Rect(x: 0, y: 0, width: 1, height: 1)
        case .center: return Rect(x: 0.15, y: 0.1, width: 0.7, height: 0.8)
        }
    }

    /// The frame inside `area`, leaving `gap` around and between snapped windows.
    public func frame(in area: Rect, gap: Double) -> Rect {
        let u = unit
        let x0 = area.x + u.minX * area.width, x1 = area.x + u.maxX * area.width
        let y0 = area.y + u.minY * area.height, y1 = area.y + u.maxY * area.height
        let left = u.minX < 0.001 ? gap : gap / 2, right = u.maxX > 0.999 ? gap : gap / 2
        let top = u.minY < 0.001 ? gap : gap / 2, bottom = u.maxY > 0.999 ? gap : gap / 2
        return Rect(x: x0 + left, y: y0 + top, width: x1 - x0 - left - right, height: y1 - y0 - top - bottom).rounded()
    }
}
