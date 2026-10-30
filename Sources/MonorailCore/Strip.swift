/// Identifier of a window. On macOS this is the `CGWindowID`.
public typealias WindowID = UInt32

public enum Direction: String, Codable, Sendable {
    case left, right, up, down
}

/// A screen edge a column can be pinned to.
public enum PinSide: String, Codable, Sendable {
    case left, right
}

/// One column of the strip: a single window, several stacked vertically,
/// tabs, or a grid of tiles (a "slide").
public struct Column: Equatable, Codable, Sendable {
    public var windows: [WindowID]
    /// Index into `windows` of the window that has focus within the column.
    public var active: Int
    /// Width as a fraction of the usable display width.
    public var width: Double
    /// Full width overrides `width` until toggled off, so the previous width survives.
    public var isFullWidth: Bool
    /// Tabbed columns show one window at a time, full height, under a tab bar.
    public var isTabbed: Bool
    /// How the column's windows share its space (ignored while tabbed).
    public var arrangement: Arrangement
    /// The main window's share of the column in the main layouts.
    public var split: Double
    /// Pinned columns stay at a screen edge while the rest of the strip scrolls.
    public var pin: PinSide?
    /// Set when the user arranged this column by hand. Automatic grouping
    /// leaves custom columns alone until the strip is reset to smart pairs.
    public var isCustom: Bool

    public init(
        windows: [WindowID],
        active: Int = 0,
        width: Double,
        isFullWidth: Bool = false,
        isTabbed: Bool = false,
        arrangement: Arrangement = .stack,
        split: Double = Arrangement.defaultSplit,
        pin: PinSide? = nil,
        isCustom: Bool = false
    ) {
        self.windows = windows
        self.active = active
        self.width = LayoutConfig.clampWidth(width)
        self.isFullWidth = isFullWidth
        self.isTabbed = isTabbed
        self.arrangement = arrangement
        self.split = split
        self.pin = pin
        self.isCustom = isCustom
    }

    /// More than six windows in one slide is too crowded to use.
    public static let maximumWindows = 6

    public var isFull: Bool { windows.count >= Self.maximumWindows }
    public var effectiveWidth: Double { isFullWidth ? 1 : width }
    public var activeWindow: WindowID { windows[active] }

    /// A tiled column is a slide: anything other than a plain stack.
    public var isTiled: Bool { arrangement != .stack }

    /// Tile rectangles in unit coordinates for the column's windows.
    public var unitFrames: [Rect] { arrangement.unitFrames(count: windows.count, split: split) }

    private enum CodingKeys: String, CodingKey {
        case windows, active, width, isFullWidth, isTabbed, arrangement, split, isGrid, pin, isCustom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            windows: try c.decode([WindowID].self, forKey: .windows),
            active: try c.decodeIfPresent(Int.self, forKey: .active) ?? 0,
            width: try c.decodeIfPresent(Double.self, forKey: .width) ?? 0.5,
            isFullWidth: try c.decodeIfPresent(Bool.self, forKey: .isFullWidth) ?? false,
            isTabbed: try c.decodeIfPresent(Bool.self, forKey: .isTabbed) ?? false,
            arrangement: try c.decodeIfPresent(Arrangement.self, forKey: .arrangement)
                ?? ((try c.decodeIfPresent(Bool.self, forKey: .isGrid)) == true ? .grid : .stack),
            split: try c.decodeIfPresent(Double.self, forKey: .split) ?? Arrangement.defaultSplit,
            pin: try c.decodeIfPresent(PinSide.self, forKey: .pin),
            isCustom: try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        )
        active = min(max(active, 0), max(windows.count - 1, 0))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(windows, forKey: .windows)
        try c.encode(active, forKey: .active)
        try c.encode(width, forKey: .width)
        try c.encode(isFullWidth, forKey: .isFullWidth)
        try c.encode(isTabbed, forKey: .isTabbed)
        try c.encode(arrangement, forKey: .arrangement)
        try c.encode(split, forKey: .split)
        try c.encodeIfPresent(pin, forKey: .pin)
        try c.encode(isCustom, forKey: .isCustom)
    }
}

/// Where a window should go, as computed by `Strip.layout`.
public struct Placement: Equatable, Sendable {
    public var window: WindowID
    public var frame: Rect
    /// True when the column is entirely outside the viewport and has been
    /// moved to the display edge with only a sliver showing.
    public var isParked: Bool

    /// True for the windows of a tabbed column that are behind the active tab.
    public var isHiddenTab: Bool

    public init(window: WindowID, frame: Rect, isParked: Bool, isHiddenTab: Bool = false) {
        self.window = window
        self.frame = frame
        self.isParked = isParked
        self.isHiddenTab = isHiddenTab
    }
}

/// The tab bar of a tabbed column, as computed by `Strip.tabBars`.
public struct TabBar: Equatable, Sendable {
    public var column: Int
    public var frame: Rect
    public var windows: [WindowID]
    public var active: Int
}

/// A horizontal strip of columns that extends past the display edges.
///
/// The strip is a pure value: it knows nothing about real windows or
/// displays. The engine applies the frames that `layout` returns.
/// `scroll` is the strip-space x coordinate shown at the left edge of the
/// usable viewport area.
public struct Strip: Equatable, Codable, Sendable {
    public private(set) var columns: [Column] = []
    public private(set) var focusedColumn: Int = 0
    public var scroll: Double = 0

    public init() {}

    public init(columns: [Column], focusedColumn: Int = 0, scroll: Double = 0) {
        self.columns = columns.filter { !$0.windows.isEmpty }
        self.focusedColumn = self.columns.isEmpty ? 0 : min(max(focusedColumn, 0), self.columns.count - 1)
        self.scroll = scroll
    }

    // MARK: - Queries

    public var isEmpty: Bool { columns.isEmpty }
    public var windowCount: Int { columns.reduce(0) { $0 + $1.windows.count } }
    public var allWindows: [WindowID] { columns.flatMap(\.windows) }

    public var focusedWindow: WindowID? {
        columns.indices.contains(focusedColumn) ? columns[focusedColumn].activeWindow : nil
    }

    public func contains(_ window: WindowID) -> Bool {
        locate(window) != nil
    }

    /// Column and row of `window`, if it is on the strip.
    public func locate(_ window: WindowID) -> (column: Int, row: Int)? {
        for (c, column) in columns.enumerated() {
            if let r = column.windows.firstIndex(of: window) { return (c, r) }
        }
        return nil
    }

    // MARK: - Membership

    public enum InsertPosition: String, Codable, Sendable {
        case afterFocused, start, end
    }

    /// Adds `window` as a new column. Returns false if it was already present.
    @discardableResult
    public mutating func insert(
        _ window: WindowID,
        width: Double,
        position: InsertPosition = .afterFocused,
        focus: Bool = true
    ) -> Bool {
        guard !contains(window) else { return false }
        let column = Column(windows: [window], width: width)
        let index: Int
        switch position {
        case .afterFocused: index = columns.isEmpty ? 0 : focusedColumn + 1
        case .start: index = 0
        case .end: index = columns.count
        }
        columns.insert(column, at: index)
        if focus || columns.count == 1 {
            focusedColumn = index
        } else if index <= focusedColumn {
            focusedColumn += 1
        }
        return true
    }

    /// Removes `window`. Focus moves to the neighbouring column on the left
    /// (or the right when there is none). Returns false if it was not present.
    @discardableResult
    public mutating func remove(_ window: WindowID) -> Bool {
        guard let (c, r) = locate(window) else { return false }
        columns[c].windows.remove(at: r)
        if columns[c].windows.isEmpty {
            columns.remove(at: c)
            if c < focusedColumn || (c == focusedColumn && c > 0) {
                focusedColumn -= 1
            }
            focusedColumn = columns.isEmpty ? 0 : min(focusedColumn, columns.count - 1)
        } else {
            if r < columns[c].active { columns[c].active -= 1 }
            columns[c].active = min(columns[c].active, columns[c].windows.count - 1)
        }
        return true
    }

    // MARK: - Focus

    /// Focuses `window`. Returns false if it is not on the strip.
    @discardableResult
    public mutating func focus(_ window: WindowID) -> Bool {
        guard let (c, r) = locate(window) else { return false }
        focusedColumn = c
        columns[c].active = r
        return true
    }

    /// Moves focus one step: between the tiles of a slide first, then to the
    /// neighbouring column. Returns false at the edge of the strip.
    @discardableResult
    public mutating func moveFocus(_ direction: Direction) -> Bool {
        guard !columns.isEmpty else { return false }
        let column = columns[focusedColumn]
        if let target = tile(nextTo: column.active, in: column, direction) {
            columns[focusedColumn].active = target
            return true
        }
        switch direction {
        case .left, .right:
            let next = focusedColumn + (direction == .left ? -1 : 1)
            guard columns.indices.contains(next) else { return false }
            let crossY = column.isTabbed ? 0.5 : column.unitFrames[column.active].midY
            focusedColumn = next
            enter(fromRight: direction == .left, crossY: crossY)
            return true
        case .up, .down:
            return false
        }
    }

    /// The tile next to `index` within the column: by position for slides and
    /// stacks, previous/next for tabs.
    private func tile(nextTo index: Int, in column: Column, _ direction: Direction) -> Int? {
        if column.isTabbed {
            guard direction == .up || direction == .down else { return nil }
            let target = index + (direction == .up ? -1 : 1)
            return column.windows.indices.contains(target) ? target : nil
        }
        return column.arrangement.neighbour(of: index, count: column.windows.count, split: column.split, direction)
    }

    /// Entering a column sideways lands on a tile on the near edge.
    private mutating func enter(fromRight: Bool, crossY: Double) {
        let column = columns[focusedColumn]
        guard !column.isTabbed, column.windows.count > 1 else { return }
        columns[focusedColumn].active = column.arrangement.entryTile(
            count: column.windows.count, split: column.split, fromRight: fromRight,
            preferred: column.active, crossY: crossY)
    }

    /// Focuses the column at `index`, clamped to the strip.
    public mutating func focusColumn(at index: Int) {
        guard !columns.isEmpty else { return }
        focusedColumn = min(max(index, 0), columns.count - 1)
    }

    // MARK: - Moving

    /// Moves the focused window: swaps it with the neighbouring tile of its
    /// slide if there is one, otherwise moves the whole column left or right.
    @discardableResult
    public mutating func moveFocused(_ direction: Direction) -> Bool {
        guard !columns.isEmpty else { return false }
        var column = columns[focusedColumn]
        if let target = tile(nextTo: column.active, in: column, direction) {
            column.windows.swapAt(column.active, target)
            column.active = target
            columns[focusedColumn] = column
            return true
        }
        switch direction {
        case .left:
            guard focusedColumn > 0 else { return false }
            columns.swapAt(focusedColumn, focusedColumn - 1)
            focusedColumn -= 1
        case .right:
            guard focusedColumn < columns.count - 1 else { return false }
            columns.swapAt(focusedColumn, focusedColumn + 1)
            focusedColumn += 1
        case .up, .down:
            return false
        }
        return true
    }

    /// Moves the column at `from` to position `to`, keeping focus on the same column.
    public mutating func moveColumn(from: Int, to: Int) {
        guard columns.indices.contains(from) else { return }
        let target = min(max(to, 0), columns.count - 1)
        guard target != from else { return }
        let focused = columns[focusedColumn].activeWindow
        let column = columns.remove(at: from)
        columns.insert(column, at: target)
        focus(focused)
    }

    // MARK: - Stacks

    /// Moves the focused window into the bottom of the column on its left.
    @discardableResult
    public mutating func consumeIntoLeft() -> Bool {
        guard focusedColumn > 0, !columns[focusedColumn - 1].isFull, let window = focusedWindow else { return false }
        let target = focusedColumn - 1
        var source = columns[focusedColumn]
        source.windows.remove(at: source.active)
        if source.windows.isEmpty {
            columns.remove(at: focusedColumn)
        } else {
            source.active = min(source.active, source.windows.count - 1)
            columns[focusedColumn] = source
        }
        columns[target].windows.append(window)
        columns[target].active = columns[target].windows.count - 1
        columns[target].isCustom = true
        focusedColumn = target
        return true
    }

    /// Moves the focused window into the bottom of the column on its right.
    @discardableResult
    public mutating func consumeIntoRight() -> Bool {
        guard focusedColumn < columns.count - 1, !columns[focusedColumn + 1].isFull, let window = focusedWindow else {
            return false
        }
        var source = columns[focusedColumn]
        source.windows.remove(at: source.active)
        var target = focusedColumn + 1
        if source.windows.isEmpty {
            columns.remove(at: focusedColumn)
            target -= 1
        } else {
            source.active = min(source.active, source.windows.count - 1)
            columns[focusedColumn] = source
        }
        columns[target].windows.append(window)
        columns[target].active = columns[target].windows.count - 1
        columns[target].isCustom = true
        focusedColumn = target
        return true
    }

    /// Takes the focused window out of its stack into its own column on the left.
    @discardableResult
    public mutating func expelLeft() -> Bool {
        guard expel() else { return false }
        columns.swapAt(focusedColumn, focusedColumn - 1)
        focusedColumn -= 1
        return true
    }

    /// Takes the focused window out of its stack into its own column on the right.
    @discardableResult
    public mutating func expel() -> Bool {
        guard columns.indices.contains(focusedColumn), columns[focusedColumn].windows.count > 1 else {
            return false
        }
        var source = columns[focusedColumn]
        let window = source.windows.remove(at: source.active)
        source.active = min(source.active, source.windows.count - 1)
        source.isCustom = true
        columns[focusedColumn] = source
        columns.insert(Column(windows: [window], width: source.width, isCustom: true), at: focusedColumn + 1)
        focusedColumn += 1
        return true
    }

    // MARK: - Slides and moving windows between columns

    /// Inserts a new column holding `windows` as grid tiles.
    public mutating func insertSlide(
        _ windows: [WindowID], width: Double, arrangement: Arrangement = .grid,
        position: InsertPosition = .afterFocused, focus: Bool = true
    ) {
        let fresh = windows.filter { !contains($0) }
        guard !fresh.isEmpty else { return }
        let column = Column(windows: fresh, active: fresh.count - 1, width: width, arrangement: arrangement)
        let index: Int
        switch position {
        case .afterFocused: index = columns.isEmpty ? 0 : focusedColumn + 1
        case .start: index = 0
        case .end: index = columns.count
        }
        columns.insert(column, at: index)
        if focus || columns.count == 1 {
            focusedColumn = index
        } else if index <= focusedColumn {
            focusedColumn += 1
        }
    }

    /// Adds a window that is not on the strip to the column at `index`.
    public mutating func add(_ window: WindowID, toColumn index: Int, focus: Bool = true, custom: Bool = false) {
        guard columns.indices.contains(index), !contains(window) else { return }
        guard !columns[index].isFull else {
            // A full slide: the window gets a slide of its own next to it.
            columns.insert(Column(windows: [window], width: columns[index].width, arrangement: columns[index].arrangement), at: index + 1)
            if focus { focusedColumn = index + 1 } else if index + 1 <= focusedColumn { focusedColumn += 1 }
            return
        }
        columns[index].windows.append(window)
        if custom { columns[index].isCustom = true }
        if focus {
            focusedColumn = index
            columns[index].active = columns[index].windows.count - 1
        }
    }

    /// Moves `window` into the column that currently holds `target`'s windows.
    /// Returns false if nothing changed.
    @discardableResult
    public mutating func moveWindow(_ window: WindowID, intoColumn target: Int) -> Bool {
        guard columns.indices.contains(target), let (source, _) = locate(window), source != target,
            !columns[target].isFull
        else {
            return false
        }
        let anchor = columns[target].activeWindow
        remove(window)
        guard let (newTarget, _) = locate(anchor) else { return false }
        columns[newTarget].windows.append(window)
        columns[newTarget].isCustom = true
        focus(window)
        return true
    }

    /// Moves `window` out into a new column of its own at `index` (0...columns.count).
    public mutating func moveWindow(_ window: WindowID, toNewColumnAt index: Int, width: Double) {
        guard let (source, _) = locate(window) else { return }
        // Work out where `index` lands once the window has been taken out.
        let sourceVanishes = columns[source].windows.count == 1
        var target = min(max(index, 0), columns.count)
        if sourceVanishes && source < target { target -= 1 }
        let keepWidth = sourceVanishes ? columns[source].width : width
        remove(window)
        target = min(target, columns.count)
        columns.insert(Column(windows: [window], width: keepWidth, isCustom: true), at: target)
        focusedColumn = target
    }

    /// Replaces the strip's columns with full-width grid slides, one per group,
    /// keeping pinned columns and the focused window.
    public mutating func regroup(
        _ groups: [[WindowID]], width: Double, arrangement: ([WindowID]) -> Arrangement = { _ in .grid }
    ) {
        let focused = focusedWindow
        let pinned = columns.filter { $0.pin != nil }
        let pinnedWindows = Set(pinned.flatMap(\.windows))
        var fresh = pinned
        for group in groups {
            let members = group.filter { !pinnedWindows.contains($0) }
            guard !members.isEmpty else { continue }
            fresh.append(Column(windows: members, width: width, arrangement: arrangement(members)))
        }
        columns = fresh
        focusedColumn = 0
        if let focused { focus(focused) }
    }

    // MARK: - Resizing inside a slide

    /// The user resized `window` to `fraction` of its slide (width, height).
    /// Adjusts the slide so the other windows fill the rest: main layouts move
    /// their split; a side-by-side or stacked pair becomes main + side or main
    /// + bottom. Returns false if this slide can't follow a resize.
    @discardableResult
    public mutating func resizeTile(_ window: WindowID, toFraction fraction: (width: Double, height: Double)) -> Bool {
        guard let (c, r) = locate(window), !columns[c].isTabbed, columns[c].windows.count >= 2 else { return false }
        var column = columns[c]
        let count = column.windows.count
        let share: Double
        switch column.arrangement {
        case .mainLeft:
            share = r == 0 ? fraction.width : 1 - fraction.width
        case .mainTop:
            share = r == 0 ? fraction.height : 1 - fraction.height
        case .columns where count == 2, .grid where count == 2:
            column.arrangement = .mainLeft
            share = r == 0 ? fraction.width : 1 - fraction.width
        case .stack where count == 2:
            column.arrangement = .mainTop
            share = r == 0 ? fraction.height : 1 - fraction.height
        default:
            return false
        }
        let range = Arrangement.splitRange
        column.split = min(max(share, range.lowerBound), range.upperBound)
        column.isCustom = true
        columns[c] = column
        return true
    }

    /// Leaves `window` alone in its slide and moves the slide's other windows
    /// into a new slide right after it.
    @discardableResult
    public mutating func moveOthersOut(keeping window: WindowID) -> Bool {
        guard let (c, _) = locate(window), columns[c].windows.count > 1 else { return false }
        var column = columns[c]
        let others = column.windows.filter { $0 != window }
        column.windows = [window]
        column.active = 0
        column.isCustom = true
        columns[c] = column
        columns.insert(
            Column(windows: others, width: column.width, arrangement: column.arrangement, isCustom: true), at: c + 1)
        focusedColumn = c
        return true
    }

    // MARK: - Remembering places

    /// Where a window sits, so it can go back there after being hidden,
    /// minimised, closed and reopened, or its app relaunched.
    public struct Slot: Equatable, Codable, Sendable {
        public var columnIndex: Int
        public var row: Int
        /// The other windows that shared its column.
        public var mates: [WindowID]
        public var width: Double
        public var arrangement: Arrangement
        public var isCustom: Bool
    }

    public func slot(of window: WindowID) -> Slot? {
        guard let (c, r) = locate(window) else { return nil }
        let column = columns[c]
        return Slot(
            columnIndex: c, row: r, mates: column.windows.filter { $0 != window },
            width: column.width, arrangement: column.arrangement, isCustom: column.isCustom)
    }

    /// Puts `window` back where `slot` says: into its old column if any of its
    /// column mates are still there, otherwise as a column at its old index.
    public mutating func restore(_ window: WindowID, to slot: Slot, focus: Bool = true) {
        guard !contains(window) else { return }
        if let mate = slot.mates.first(where: contains), let (c, _) = locate(mate), !columns[c].isFull {
            let row = min(slot.row, columns[c].windows.count)
            columns[c].windows.insert(window, at: row)
            if columns[c].active >= row && columns[c].windows.count > 1 { columns[c].active += 1 }
            if focus {
                focusedColumn = c
                columns[c].active = row
            }
            return
        }
        let index = min(max(slot.columnIndex, 0), columns.count)
        columns.insert(
            Column(windows: [window], width: slot.width, arrangement: slot.arrangement, isCustom: slot.isCustom),
            at: index)
        if focus || columns.count == 1 {
            focusedColumn = index
        } else if index <= focusedColumn {
            focusedColumn += 1
        }
    }

    // MARK: - Widths

    /// Steps the focused column to the next (or previous) width preset, wrapping around.
    public mutating func cycleWidth(presets: [Double], forward: Bool = true) {
        guard columns.indices.contains(focusedColumn), !presets.isEmpty else { return }
        let current = columns[focusedColumn].effectiveWidth
        let sorted = presets.sorted()
        let next: Double
        if forward {
            next = sorted.first(where: { $0 > current + 0.01 }) ?? sorted[0]
        } else {
            next = sorted.last(where: { $0 < current - 0.01 }) ?? sorted[sorted.count - 1]
        }
        columns[focusedColumn].width = LayoutConfig.clampWidth(next)
        columns[focusedColumn].isFullWidth = false
    }

    /// Grows or shrinks the focused column by `delta` (a fraction of the usable width).
    public mutating func adjustWidth(by delta: Double) {
        guard columns.indices.contains(focusedColumn) else { return }
        let current = columns[focusedColumn].effectiveWidth
        columns[focusedColumn].width = LayoutConfig.clampWidth(current + delta)
        columns[focusedColumn].isFullWidth = false
    }

    public mutating func toggleFullWidth() {
        guard columns.indices.contains(focusedColumn) else { return }
        columns[focusedColumn].isFullWidth.toggle()
    }

    /// Sets the width of the column holding `window`, e.g. after the user resized it.
    public mutating func setWidth(_ width: Double, of window: WindowID) {
        guard let (c, _) = locate(window) else { return }
        columns[c].width = LayoutConfig.clampWidth(width)
        columns[c].isFullWidth = false
    }

    // MARK: - Pinning and tabs

    /// Pins the focused column to `side`, or unpins it if it is already pinned there.
    public mutating func togglePin(_ side: PinSide) {
        guard columns.indices.contains(focusedColumn) else { return }
        columns[focusedColumn].pin = columns[focusedColumn].pin == side ? nil : side
    }

    public mutating func toggleTabbed() {
        guard columns.indices.contains(focusedColumn) else { return }
        columns[focusedColumn].isTabbed.toggle()
    }

    /// Steps the focused column to the next arrangement (grid → columns → main
    /// + side → main + bottom → rows), leaving tabs.
    public mutating func cycleArrangement() {
        guard columns.indices.contains(focusedColumn) else { return }
        if columns[focusedColumn].isTabbed {
            columns[focusedColumn].isTabbed = false
        } else {
            columns[focusedColumn].arrangement = columns[focusedColumn].arrangement.next
        }
    }

    public mutating func setArrangement(_ arrangement: Arrangement) {
        guard columns.indices.contains(focusedColumn) else { return }
        columns[focusedColumn].isTabbed = false
        columns[focusedColumn].arrangement = arrangement
    }

    /// Grows or shrinks the main window of the focused column's main layout.
    public mutating func adjustSplit(by delta: Double) {
        guard columns.indices.contains(focusedColumn) else { return }
        let range = Arrangement.splitRange
        columns[focusedColumn].split = min(max(columns[focusedColumn].split + delta, range.lowerBound), range.upperBound)
    }

    /// Makes the focused window the column's first (main) window.
    public mutating func promoteToMain() {
        guard columns.indices.contains(focusedColumn) else { return }
        var column = columns[focusedColumn]
        guard column.active > 0 else { return }
        let window = column.windows.remove(at: column.active)
        column.windows.insert(window, at: 0)
        column.active = 0
        columns[focusedColumn] = column
    }

    // MARK: - Geometry

    /// Width of column `index` in points.
    public func width(ofColumn index: Int, config: LayoutConfig, viewportWidth: Double) -> Double {
        config.columnWidth(fraction: columns[index].effectiveWidth, viewportWidth: viewportWidth)
    }

    /// The part of the usable width that scrolls: what pinned columns leave free.
    /// `inset` is measured from the left edge of the usable area.
    public func scrollArea(config: LayoutConfig, viewportWidth: Double) -> (inset: Double, width: Double) {
        var left = 0.0
        var right = 0.0
        for index in columns.indices {
            guard let pin = columns[index].pin else { continue }
            let w = width(ofColumn: index, config: config, viewportWidth: viewportWidth) + config.gap
            if pin == .left { left += w } else { right += w }
        }
        let usable = config.usableWidth(viewportWidth)
        return (left, max(usable - left - right, 1))
    }

    /// Strip-space x coordinate of each column's left edge. Pinned columns take no
    /// space on the scrolling strip; their entry is the offset of the next column.
    public func columnOffsets(config: LayoutConfig, viewportWidth: Double) -> [Double] {
        var offsets: [Double] = []
        offsets.reserveCapacity(columns.count)
        var x = 0.0
        for index in columns.indices {
            offsets.append(x)
            if columns[index].pin == nil {
                x += width(ofColumn: index, config: config, viewportWidth: viewportWidth) + config.gap
            }
        }
        return offsets
    }

    /// Total width of the scrolling (unpinned) columns and the gaps between them.
    public func totalWidth(config: LayoutConfig, viewportWidth: Double) -> Double {
        let scrolling = columns.indices.filter { columns[$0].pin == nil }
        guard !scrolling.isEmpty else { return 0 }
        let widths = scrolling.reduce(0.0) {
            $0 + width(ofColumn: $1, config: config, viewportWidth: viewportWidth)
        }
        return widths + config.gap * Double(scrolling.count - 1)
    }

    /// Scrolls so the focused column is visible, following `config.centerMode`.
    public mutating func revealFocused(config: LayoutConfig, viewportWidth: Double) {
        guard columns.indices.contains(focusedColumn) else {
            scroll = 0
            return
        }
        guard columns[focusedColumn].pin == nil else { return }
        let usable = scrollArea(config: config, viewportWidth: viewportWidth).width
        let x = columnOffsets(config: config, viewportWidth: viewportWidth)[focusedColumn]
        let w = width(ofColumn: focusedColumn, config: config, viewportWidth: viewportWidth)
        let epsilon = 0.5

        if config.centerMode == .always {
            scroll = w >= usable ? x : x + w / 2 - usable / 2
            return
        }
        let fullyVisible = x >= scroll - epsilon && x + w <= scroll + usable + epsilon
        if fullyVisible { return }

        if w >= usable {
            scroll = x
        } else if config.centerMode == .onOverflow {
            scroll = x + w / 2 - usable / 2
        } else if x < scroll {
            scroll = x
        } else {
            scroll = x + w - usable
        }
        clampScroll(config: config, viewportWidth: viewportWidth)
    }

    /// Centres the focused column in the scrolling area.
    public mutating func centerFocused(config: LayoutConfig, viewportWidth: Double) {
        guard columns.indices.contains(focusedColumn), columns[focusedColumn].pin == nil else { return }
        let usable = scrollArea(config: config, viewportWidth: viewportWidth).width
        let x = columnOffsets(config: config, viewportWidth: viewportWidth)[focusedColumn]
        let w = width(ofColumn: focusedColumn, config: config, viewportWidth: viewportWidth)
        scroll = x + w / 2 - usable / 2
    }

    /// Keeps the strip from showing empty space when it does not need to:
    /// no blank area on the left, and none on the right while columns are
    /// hidden on the left.
    public mutating func clampScroll(config: LayoutConfig, viewportWidth: Double) {
        let usable = scrollArea(config: config, viewportWidth: viewportWidth).width
        let total = totalWidth(config: config, viewportWidth: viewportWidth)
        scroll = min(scroll, max(0, total - usable))
        scroll = max(scroll, 0)
    }

    /// Scrolls freely by `delta` points (trackpad swipe), keeping at least half a
    /// viewport of strip on screen.
    public mutating func scroll(by delta: Double, config: LayoutConfig, viewportWidth: Double) {
        let usable = scrollArea(config: config, viewportWidth: viewportWidth).width
        let total = totalWidth(config: config, viewportWidth: viewportWidth)
        scroll = min(max(scroll + delta, -usable / 2), max(total - usable / 2, -usable / 2))
    }

    /// Ends a free scroll: settles on the nearest column edge and focuses the
    /// column closest to the centre of the viewport.
    public mutating func settle(config: LayoutConfig, viewportWidth: Double) {
        let scrolling = columns.indices.filter { columns[$0].pin == nil }
        guard !scrolling.isEmpty else {
            scroll = 0
            return
        }
        let usable = scrollArea(config: config, viewportWidth: viewportWidth).width
        let offsets = columnOffsets(config: config, viewportWidth: viewportWidth)
        var candidates: [Double] = []
        for index in scrolling {
            let w = width(ofColumn: index, config: config, viewportWidth: viewportWidth)
            candidates.append(offsets[index])
            candidates.append(offsets[index] + w - usable)
        }
        if let nearest = candidates.min(by: { abs($0 - scroll) < abs($1 - scroll) }) {
            scroll = nearest
        }
        clampScroll(config: config, viewportWidth: viewportWidth)

        let centre = scroll + usable / 2
        var best = scrolling[0]
        var bestDistance = Double.infinity
        for index in scrolling {
            let w = width(ofColumn: index, config: config, viewportWidth: viewportWidth)
            let distance = abs(offsets[index] + w / 2 - centre)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        focusedColumn = best
    }

    /// Where each column sits on screen, in viewport coordinates, and whether it
    /// is parked. Columns entirely outside the scrolling area are parked at the
    /// display edge with `config.parkSliver` points showing.
    public func columnFrames(config: LayoutConfig, viewport: Rect) -> [(frame: Rect, isParked: Bool)] {
        let offsets = columnOffsets(config: config, viewportWidth: viewport.width)
        let area = scrollArea(config: config, viewportWidth: viewport.width)
        let usableHeight = max(viewport.height - 2 * config.edgeGap, 1)
        let usableMinX = viewport.minX + config.edgeGap
        let areaMinX = usableMinX + area.inset
        let areaMaxX = areaMinX + area.width
        let y = viewport.minY + config.edgeGap

        var leftPinned = usableMinX
        var rightPinned = viewport.maxX - config.edgeGap
        var result: [(frame: Rect, isParked: Bool)] = []
        result.reserveCapacity(columns.count)

        for (index, column) in columns.enumerated() {
            let w = width(ofColumn: index, config: config, viewportWidth: viewport.width)
            var x: Double
            var parked = false
            switch column.pin {
            case .left?:
                x = leftPinned
                leftPinned += w + config.gap
            case .right?:
                rightPinned -= w
                x = rightPinned
                rightPinned -= config.gap
            case nil:
                x = areaMinX + offsets[index] - scroll
                if x + w <= areaMinX {
                    x = viewport.minX - w + config.parkSliver
                    parked = true
                } else if x >= areaMaxX {
                    x = viewport.maxX - config.parkSliver
                    parked = true
                }
            }
            if config.direction == .rightToLeft {
                // Mirror around the viewport: the strip grows to the left.
                x = viewport.minX + viewport.maxX - x - w
            }
            result.append((Rect(x: x, y: y, width: w, height: usableHeight), parked))
        }
        return result
    }

    /// Frames for every window on the strip, in viewport coordinates.
    public func layout(config: LayoutConfig, viewport: Rect) -> [Placement] {
        let frames = columnFrames(config: config, viewport: viewport)
        var placements: [Placement] = []
        placements.reserveCapacity(windowCount)

        for (index, column) in columns.enumerated() {
            let (columnFrame, parked) = frames[index]
            if column.isTabbed {
                let bar = min(config.tabBarHeight, columnFrame.height / 2)
                let frame = Rect(
                    x: columnFrame.x, y: columnFrame.y + bar,
                    width: columnFrame.width, height: columnFrame.height - bar
                ).rounded()
                for (row, window) in column.windows.enumerated() {
                    placements.append(
                        Placement(window: window, frame: frame, isParked: parked, isHiddenTab: row != column.active))
                }
                continue
            }
            let mirrored = config.direction == .rightToLeft
            for (index, unit) in column.unitFrames.enumerated() {
                let tile = mirrored ? Rect(x: 1 - unit.maxX, y: unit.y, width: unit.width, height: unit.height) : unit
                placements.append(
                    Placement(
                        window: column.windows[index],
                        frame: Self.tileFrame(tile, in: columnFrame, gap: config.gap),
                        isParked: parked))
            }
        }
        return placements
    }

    /// Maps a unit tile rectangle into `frame`, leaving `gap` between tiles
    /// but none at the column's outer edges.
    static func tileFrame(_ unit: Rect, in frame: Rect, gap: Double) -> Rect {
        let epsilon = 0.0001
        var minX = frame.x + unit.minX * frame.width
        var maxX = frame.x + unit.maxX * frame.width
        var minY = frame.y + unit.minY * frame.height
        var maxY = frame.y + unit.maxY * frame.height
        if unit.minX > epsilon { minX += gap / 2 }
        if unit.maxX < 1 - epsilon { maxX -= gap / 2 }
        if unit.minY > epsilon { minY += gap / 2 }
        if unit.maxY < 1 - epsilon { maxY -= gap / 2 }
        return Rect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1)).rounded()
    }

    /// Tab bars for tabbed columns that are on screen.
    public func tabBars(config: LayoutConfig, viewport: Rect) -> [TabBar] {
        let frames = columnFrames(config: config, viewport: viewport)
        return columns.enumerated().compactMap { index, column in
            let (frame, parked) = frames[index]
            guard column.isTabbed, !parked else { return nil }
            let height = min(config.tabBarHeight, frame.height / 2)
            let bar = Rect(x: frame.x, y: frame.y, width: frame.width, height: height - 2).rounded()
            return TabBar(column: index, frame: bar, windows: column.windows, active: column.active)
        }
    }
}
