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
    /// Grid columns tile their windows two across: 2 side by side, 3 or 4 as a 2×2 grid.
    public var isGrid: Bool
    /// Pinned columns stay at a screen edge while the rest of the strip scrolls.
    public var pin: PinSide?

    public init(
        windows: [WindowID],
        active: Int = 0,
        width: Double,
        isFullWidth: Bool = false,
        isTabbed: Bool = false,
        isGrid: Bool = false,
        pin: PinSide? = nil
    ) {
        self.windows = windows
        self.active = active
        self.width = LayoutConfig.clampWidth(width)
        self.isFullWidth = isFullWidth
        self.isTabbed = isTabbed
        self.isGrid = isGrid
        self.pin = pin
    }

    public var effectiveWidth: Double { isFullWidth ? 1 : width }
    public var activeWindow: WindowID { windows[active] }

    /// Number of tile columns when laid out as a grid.
    public var gridColumns: Int { isGrid && windows.count > 1 ? 2 : 1 }

    /// Row and column of tile `index` in grid layout.
    public func gridCell(_ index: Int) -> (row: Int, column: Int) {
        (index / gridColumns, index % gridColumns)
    }

    private enum CodingKeys: String, CodingKey {
        case windows, active, width, isFullWidth, isTabbed, isGrid, pin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            windows: try c.decode([WindowID].self, forKey: .windows),
            active: try c.decodeIfPresent(Int.self, forKey: .active) ?? 0,
            width: try c.decodeIfPresent(Double.self, forKey: .width) ?? 0.5,
            isFullWidth: try c.decodeIfPresent(Bool.self, forKey: .isFullWidth) ?? false,
            isTabbed: try c.decodeIfPresent(Bool.self, forKey: .isTabbed) ?? false,
            isGrid: try c.decodeIfPresent(Bool.self, forKey: .isGrid) ?? false,
            pin: try c.decodeIfPresent(PinSide.self, forKey: .pin)
        )
        active = min(max(active, 0), max(windows.count - 1, 0))
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

    /// Moves focus one step. Returns false at the edge of the strip or stack.
    @discardableResult
    public mutating func moveFocus(_ direction: Direction) -> Bool {
        guard !columns.isEmpty else { return false }
        let column = columns[focusedColumn]
        // Inside a grid, move between tiles first.
        if column.isGrid, let target = gridNeighbour(of: column.active, in: column, direction) {
            columns[focusedColumn].active = target
            return true
        }
        switch direction {
        case .left:
            guard focusedColumn > 0 else { return false }
            focusedColumn -= 1
            enterGrid(fromRight: true)
        case .right:
            guard focusedColumn < columns.count - 1 else { return false }
            focusedColumn += 1
            enterGrid(fromRight: false)
        case .up:
            guard !column.isGrid, column.active > 0 else { return false }
            columns[focusedColumn].active -= 1
        case .down:
            guard !column.isGrid, column.active < column.windows.count - 1 else { return false }
            columns[focusedColumn].active += 1
        }
        return true
    }

    /// The tile next to `index` in a grid column, if there is one.
    private func gridNeighbour(of index: Int, in column: Column, _ direction: Direction) -> Int? {
        let width = column.gridColumns
        let (row, col) = column.gridCell(index)
        let target: Int
        switch direction {
        case .left:
            guard col > 0 else { return nil }
            target = index - 1
        case .right:
            guard col < width - 1 else { return nil }
            target = index + 1
        case .up:
            guard row > 0 else { return nil }
            target = index - width
        case .down:
            target = index + width
        }
        return column.windows.indices.contains(target) ? target : nil
    }

    /// Entering a grid sideways lands on the near tile of the row last used.
    private mutating func enterGrid(fromRight: Bool) {
        let column = columns[focusedColumn]
        guard column.isGrid else { return }
        let row = column.gridCell(column.active).row
        let index = row * column.gridColumns + (fromRight ? column.gridColumns - 1 : 0)
        columns[focusedColumn].active = min(index, column.windows.count - 1)
    }

    /// Focuses the column at `index`, clamped to the strip.
    public mutating func focusColumn(at index: Int) {
        guard !columns.isEmpty else { return }
        focusedColumn = min(max(index, 0), columns.count - 1)
    }

    // MARK: - Moving

    /// Moves the focused column left/right, or the focused window up/down in its stack.
    @discardableResult
    public mutating func moveFocused(_ direction: Direction) -> Bool {
        guard !columns.isEmpty else { return false }
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
            var column = columns[focusedColumn]
            let step = column.isGrid ? column.gridColumns : 1
            let target = column.active + (direction == .up ? -step : step)
            guard column.windows.indices.contains(target) else { return false }
            column.windows.swapAt(column.active, target)
            column.active = target
            columns[focusedColumn] = column
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
        guard focusedColumn > 0, let window = focusedWindow else { return false }
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
        focusedColumn = target
        return true
    }

    /// Moves the focused window into the bottom of the column on its right.
    @discardableResult
    public mutating func consumeIntoRight() -> Bool {
        guard focusedColumn < columns.count - 1, let window = focusedWindow else { return false }
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
        columns[focusedColumn] = source
        columns.insert(Column(windows: [window], width: source.width), at: focusedColumn + 1)
        focusedColumn += 1
        return true
    }

    // MARK: - Slides and moving windows between columns

    /// Inserts a new column holding `windows` as grid tiles.
    public mutating func insertSlide(
        _ windows: [WindowID], width: Double, position: InsertPosition = .afterFocused, focus: Bool = true
    ) {
        let fresh = windows.filter { !contains($0) }
        guard !fresh.isEmpty else { return }
        let column = Column(windows: fresh, active: fresh.count - 1, width: width, isGrid: true)
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
    public mutating func add(_ window: WindowID, toColumn index: Int, focus: Bool = true) {
        guard columns.indices.contains(index), !contains(window) else { return }
        columns[index].windows.append(window)
        if focus {
            focusedColumn = index
            columns[index].active = columns[index].windows.count - 1
        }
    }

    /// Moves `window` into the column that currently holds `target`'s windows.
    /// Returns false if nothing changed.
    @discardableResult
    public mutating func moveWindow(_ window: WindowID, intoColumn target: Int) -> Bool {
        guard columns.indices.contains(target), let (source, _) = locate(window), source != target else {
            return false
        }
        let anchor = columns[target].activeWindow
        remove(window)
        guard let (newTarget, _) = locate(anchor) else { return false }
        columns[newTarget].windows.append(window)
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
        columns.insert(Column(windows: [window], width: keepWidth), at: target)
        focusedColumn = target
    }

    /// Replaces the strip's columns with full-width grid slides, one per group,
    /// keeping pinned columns and the focused window.
    public mutating func regroup(_ groups: [[WindowID]], width: Double) {
        let focused = focusedWindow
        let pinned = columns.filter { $0.pin != nil }
        let pinnedWindows = Set(pinned.flatMap(\.windows))
        var fresh = pinned
        for group in groups {
            let members = group.filter { !pinnedWindows.contains($0) }
            guard !members.isEmpty else { continue }
            fresh.append(Column(windows: members, width: width, isGrid: true))
        }
        columns = fresh
        focusedColumn = 0
        if let focused { focus(focused) }
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
        if columns[focusedColumn].isTabbed { columns[focusedColumn].isGrid = false }
    }

    public mutating func toggleGrid() {
        guard columns.indices.contains(focusedColumn) else { return }
        columns[focusedColumn].isGrid.toggle()
        if columns[focusedColumn].isGrid { columns[focusedColumn].isTabbed = false }
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
            if column.isGrid {
                let across = column.gridColumns
                let rows = (column.windows.count + across - 1) / across
                let w = (columnFrame.width - config.gap * Double(across - 1)) / Double(across)
                let h = max((columnFrame.height - config.gap * Double(rows - 1)) / Double(rows), 1)
                for (index, window) in column.windows.enumerated() {
                    let (row, col) = column.gridCell(index)
                    // A lone tile in the last row spans the full width.
                    let spans = index == column.windows.count - 1 && col == 0 && across > 1
                    let frame = Rect(
                        x: columnFrame.x + Double(col) * (w + config.gap),
                        y: columnFrame.y + Double(row) * (h + config.gap),
                        width: spans ? columnFrame.width : w,
                        height: h
                    ).rounded()
                    placements.append(Placement(window: window, frame: frame, isParked: parked))
                }
                continue
            }
            let count = Double(column.windows.count)
            let h = max((columnFrame.height - config.gap * (count - 1)) / count, 1)
            for (row, window) in column.windows.enumerated() {
                let y = columnFrame.y + Double(row) * (h + config.gap)
                let frame = Rect(x: columnFrame.x, y: y, width: columnFrame.width, height: h).rounded()
                placements.append(Placement(window: window, frame: frame, isParked: parked))
            }
        }
        return placements
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
