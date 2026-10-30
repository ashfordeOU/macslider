/// How the windows of one column (a slide) share its space.
public enum Arrangement: String, Codable, CaseIterable, Sendable {
    /// One above the other.
    case stack
    /// A grid that grows with the count: 2 side by side, 2×2, 3×2.
    case grid
    /// Side by side, full height.
    case columns
    /// One large window on the left, the rest stacked on the right.
    case mainLeft
    /// One large window on top, the rest side by side below.
    case mainTop
    /// A user-designed layout: columns side by side, each split into rows
    /// (see `Column.customRows`).
    case custom

    /// The built-in layouts, for pickers (custom ones come from Settings).
    public static let standard: [Arrangement] = [.columns, .stack, .grid, .mainLeft, .mainTop]

    public var title: String {
        switch self {
        case .stack: return "Up and down"
        case .grid: return "Grid"
        case .columns: return "Side by side"
        case .mainLeft: return "Main + side"
        case .mainTop: return "Main + bottom"
        case .custom: return "Custom"
        }
    }

    public var symbol: String {
        switch self {
        case .stack: return "rectangle.split.1x2"
        case .grid: return "square.grid.2x2"
        case .columns: return "rectangle.split.3x1"
        case .mainLeft: return "rectangle.lefthalf.inset.filled"
        case .mainTop: return "rectangle.tophalf.inset.filled"
        case .custom: return "square.grid.3x1.below.line.grid.1x2"
        }
    }

    /// The next layout when cycling.
    public var next: Arrangement {
        switch self {
        case .grid: return .columns
        case .columns: return .mainLeft
        case .mainLeft: return .mainTop
        case .mainTop: return .stack
        case .stack: return .grid
        case .custom: return .grid
        }
    }

    public static let splitRange = 0.25...0.8
    public static let defaultSplit = 0.6

    /// Number of grid columns for `count` tiles.
    public static func gridColumns(for count: Int) -> Int {
        switch count {
        case ...1: return 1
        case 2...4: return 2
        case 5...9: return 3
        default: return 4
        }
    }

    /// Tile rectangles in unit coordinates (0...1 on both axes, y down) for
    /// `count` windows. `split` is the main window's share in the main layouts.
    public func unitFrames(count: Int, split: Double = Arrangement.defaultSplit, rows: [Int]? = nil) -> [Rect] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [Rect(x: 0, y: 0, width: 1, height: 1)] }
        if self == .custom, let rows, !rows.isEmpty { return Self.customFrames(count: count, rows: rows) }
        let n = Double(count)
        let main = min(max(split, Self.splitRange.lowerBound), Self.splitRange.upperBound)

        switch self {
        case .stack:
            return (0..<count).map { Rect(x: 0, y: Double($0) / n, width: 1, height: 1 / n) }
        case .columns:
            return (0..<count).map { Rect(x: Double($0) / n, y: 0, width: 1 / n, height: 1) }
        case .grid, .custom:
            let across = Self.gridColumns(for: count)
            let rows = (count + across - 1) / across
            var frames: [Rect] = []
            for index in 0..<count {
                let row = index / across
                // The last row stretches its tiles to fill the width.
                let inRow = min(across, count - row * across)
                let col = index - row * across
                frames.append(
                    Rect(
                        x: Double(col) / Double(inRow), y: Double(row) / Double(rows),
                        width: 1 / Double(inRow), height: 1 / Double(rows)))
            }
            return frames
        case .mainLeft:
            let rest = Double(count - 1)
            return [Rect(x: 0, y: 0, width: main, height: 1)]
                + (1..<count).map {
                    Rect(x: main, y: Double($0 - 1) / rest, width: 1 - main, height: 1 / rest)
                }
        case .mainTop:
            let rest = Double(count - 1)
            return [Rect(x: 0, y: 0, width: 1, height: main)]
                + (1..<count).map {
                    Rect(x: Double($0 - 1) / rest, y: main, width: 1 / rest, height: 1 - main)
                }
        }
    }

    /// Cells of a custom layout: equal-width columns, each split into `rows[i]`
    /// equal rows. Extra windows go into the last column; missing ones leave
    /// the last cells out.
    public static func customFrames(count: Int, rows: [Int]) -> [Rect] {
        var spec = rows.map { max($0, 1) }
        let cells = spec.reduce(0, +)
        if count > cells {
            spec[spec.count - 1] += count - cells
        } else {
            var excess = cells - count
            while excess > 0, let last = spec.indices.last {
                let take = min(excess, spec[last])
                spec[last] -= take
                excess -= take
                if spec[last] == 0 { spec.removeLast() }
            }
        }
        let width = 1.0 / Double(spec.count)
        var frames: [Rect] = []
        for (c, rowCount) in spec.enumerated() {
            let height = 1.0 / Double(rowCount)
            for r in 0..<rowCount {
                frames.append(Rect(x: Double(c) * width, y: Double(r) * height, width: width, height: height))
            }
        }
        return frames
    }

    /// The tile next to `index` in `direction`, using the tiles' positions.
    public func neighbour(of index: Int, count: Int, split: Double, rows: [Int]? = nil, _ direction: Direction) -> Int? {
        let frames = unitFrames(count: count, split: split, rows: rows)
        guard frames.indices.contains(index) else { return nil }
        let current = frames[index]
        let epsilon = 0.001
        var best: (index: Int, score: Double)?
        for (candidate, frame) in frames.enumerated() where candidate != index {
            let gap: Double
            let cross: Double
            switch direction {
            case .right:
                guard frame.minX >= current.maxX - epsilon else { continue }
                gap = frame.minX - current.maxX
                cross = abs(frame.midY - current.midY)
            case .left:
                guard frame.maxX <= current.minX + epsilon else { continue }
                gap = current.minX - frame.maxX
                cross = abs(frame.midY - current.midY)
            case .down:
                guard frame.minY >= current.maxY - epsilon else { continue }
                gap = frame.minY - current.maxY
                cross = abs(frame.midX - current.midX)
            case .up:
                guard frame.maxY <= current.minY + epsilon else { continue }
                gap = current.minY - frame.maxY
                cross = abs(frame.midX - current.midX)
            }
            let score = gap * 10 + cross
            if best == nil || score < best!.score - epsilon { best = (candidate, score) }
        }
        return best?.index
    }

    /// The tile to land on when focus enters the column from one side:
    /// a tile on that edge, preferring `preferred`, then the one nearest `crossY`.
    public func entryTile(count: Int, split: Double, rows: [Int]? = nil, fromRight: Bool, preferred: Int, crossY: Double) -> Int {
        let frames = unitFrames(count: count, split: split, rows: rows)
        let onEdge = frames.indices.filter { index in
            fromRight ? frames[index].maxX >= 1 - 0.001 : frames[index].minX <= 0.001
        }
        if onEdge.contains(preferred) { return preferred }
        return onEdge.min { abs(frames[$0].midY - crossY) < abs(frames[$1].midY - crossY) } ?? 0
    }
}

/// Which way the strip runs: new windows open to the right, or to the left.
public enum StripDirection: String, Codable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft

    public var title: String {
        self == .leftToRight ? "Left to right" : "Right to left"
    }
}
