/// How the windows of one column (a slide) share its space.
public enum Arrangement: String, Codable, CaseIterable, Sendable {
    /// One above the other.
    case stack
    /// A grid that grows with the count: 2 side by side, 2×2, 3×2, 3×3…
    case grid
    /// Side by side, full height.
    case columns
    /// One large window on the left, the rest stacked on the right.
    case mainLeft
    /// One large window on top, the rest side by side below.
    case mainTop

    public var title: String {
        switch self {
        case .stack: return "Rows"
        case .grid: return "Grid"
        case .columns: return "Columns"
        case .mainLeft: return "Main + side"
        case .mainTop: return "Main + bottom"
        }
    }

    public var symbol: String {
        switch self {
        case .stack: return "rectangle.split.1x2"
        case .grid: return "square.grid.2x2"
        case .columns: return "rectangle.split.3x1"
        case .mainLeft: return "rectangle.lefthalf.inset.filled"
        case .mainTop: return "rectangle.tophalf.inset.filled"
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
    public func unitFrames(count: Int, split: Double = Arrangement.defaultSplit) -> [Rect] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [Rect(x: 0, y: 0, width: 1, height: 1)] }
        let n = Double(count)
        let main = min(max(split, Self.splitRange.lowerBound), Self.splitRange.upperBound)

        switch self {
        case .stack:
            return (0..<count).map { Rect(x: 0, y: Double($0) / n, width: 1, height: 1 / n) }
        case .columns:
            return (0..<count).map { Rect(x: Double($0) / n, y: 0, width: 1 / n, height: 1) }
        case .grid:
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

    /// The tile next to `index` in `direction`, using the tiles' positions.
    public func neighbour(of index: Int, count: Int, split: Double, _ direction: Direction) -> Int? {
        let frames = unitFrames(count: count, split: split)
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
    public func entryTile(count: Int, split: Double, fromRight: Bool, preferred: Int, crossY: Double) -> Int {
        let frames = unitFrames(count: count, split: split)
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
