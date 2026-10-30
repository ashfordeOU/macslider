import Foundation
import XCTest
@testable import MonorailCore

final class StripTests: XCTestCase {
    // 1000pt wide viewport, no gaps: usable width 1000, a ½ column is 500pt.
    let flat = LayoutConfig(gap: 0, edgeGap: 0, parkSliver: 4, defaultWidth: 0.5)
    let viewport = Rect(x: 0, y: 0, width: 1000, height: 800)

    private func strip(_ ids: [WindowID], width: Double = 0.5) -> Strip {
        var s = Strip()
        for id in ids { s.insert(id, width: width) }
        return s
    }

    // MARK: Membership and focus

    func testInsertGoesAfterFocusedAndTakesFocus() {
        var s = strip([1, 2, 3])
        s.focus(1)
        s.insert(4, width: 0.5)
        XCTAssertEqual(s.allWindows, [1, 4, 2, 3])
        XCTAssertEqual(s.focusedWindow, 4)
    }

    func testInsertWithoutFocusKeepsFocusedWindow() {
        var s = strip([1, 2])
        s.focus(1)
        s.insert(3, width: 0.5, position: .start, focus: false)
        XCTAssertEqual(s.allWindows, [3, 1, 2])
        XCTAssertEqual(s.focusedWindow, 1)
    }

    func testInsertIgnoresDuplicates() {
        var s = strip([1])
        XCTAssertFalse(s.insert(1, width: 0.5))
        XCTAssertEqual(s.windowCount, 1)
    }

    func testRemoveFocusedMovesFocusLeft() {
        var s = strip([1, 2, 3])
        s.focus(2)
        s.remove(2)
        XCTAssertEqual(s.allWindows, [1, 3])
        XCTAssertEqual(s.focusedWindow, 1)
    }

    func testRemoveFirstFocusedMovesFocusRight() {
        var s = strip([1, 2])
        s.focus(1)
        s.remove(1)
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testRemoveColumnLeftOfFocusKeepsFocusedWindow() {
        var s = strip([1, 2, 3])
        s.remove(1)
        XCTAssertEqual(s.focusedWindow, 3)
        XCTAssertEqual(s.focusedColumn, 1)
    }

    func testRemoveLastWindowEmptiesStrip() {
        var s = strip([1])
        XCTAssertTrue(s.remove(1))
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.focusedWindow)
        XCTAssertFalse(s.remove(1))
    }

    func testMoveFocusStopsAtEdges() {
        var s = strip([1, 2])
        XCTAssertFalse(s.moveFocus(.right))
        XCTAssertTrue(s.moveFocus(.left))
        XCTAssertEqual(s.focusedWindow, 1)
        XCTAssertFalse(s.moveFocus(.left))
        XCTAssertFalse(s.moveFocus(.up))
    }

    func testFocusColumnClamps() {
        var s = strip([1, 2, 3])
        s.focusColumn(at: 0)
        XCTAssertEqual(s.focusedWindow, 1)
        s.focusColumn(at: 42)
        XCTAssertEqual(s.focusedWindow, 3)
    }

    // MARK: Moving

    func testMoveColumnSwapsAndKeepsFocus() {
        var s = strip([1, 2, 3])
        XCTAssertTrue(s.moveFocused(.left))
        XCTAssertEqual(s.allWindows, [1, 3, 2])
        XCTAssertEqual(s.focusedWindow, 3)
        s.moveColumn(from: 1, to: 0)
        XCTAssertEqual(s.allWindows, [3, 1, 2])
        XCTAssertEqual(s.focusedWindow, 3)
    }

    // MARK: Stacks

    func testConsumeAndExpel() {
        var s = strip([1, 2, 3])
        s.pairingArrangement = .stack  // up and down, as this test walks the stack vertically
        XCTAssertTrue(s.consumeIntoLeft())
        XCTAssertEqual(s.columns.count, 2)
        XCTAssertEqual(s.columns[1].windows, [2, 3])
        XCTAssertEqual(s.focusedWindow, 3)

        XCTAssertTrue(s.moveFocus(.up))
        XCTAssertEqual(s.focusedWindow, 2)
        XCTAssertTrue(s.moveFocused(.down))
        XCTAssertEqual(s.columns[1].windows, [3, 2])

        XCTAssertTrue(s.expel())
        XCTAssertEqual(s.columns.map(\.windows), [[1], [3], [2]])
        XCTAssertEqual(s.focusedWindow, 2)
        XCTAssertFalse(s.expel())
    }

    func testRemoveFromStackFixesActiveIndex() {
        var s = strip([1, 2, 3])
        s.consumeIntoLeft()
        s.consumeIntoLeft()  // columns are now [[1, 3], [2]], focus on 3
        XCTAssertEqual(s.columns.map(\.windows), [[1, 3], [2]])
        s.remove(1)
        XCTAssertEqual(s.columns.map(\.windows), [[3], [2]])
        XCTAssertEqual(s.focusedWindow, 3)
    }

    // MARK: Widths

    func testCycleWidthWraps() {
        var s = strip([1])
        let presets = [0.25, 0.5, 0.75]
        s.cycleWidth(presets: presets)
        XCTAssertEqual(s.columns[0].width, 0.75, accuracy: 0.0001)
        s.cycleWidth(presets: presets)
        XCTAssertEqual(s.columns[0].width, 0.25, accuracy: 0.0001)
        s.cycleWidth(presets: presets, forward: false)
        XCTAssertEqual(s.columns[0].width, 0.75, accuracy: 0.0001)
    }

    func testFullWidthTogglePreservesWidth() {
        var s = strip([1], width: 1.0 / 3.0)
        s.toggleFullWidth()
        XCTAssertEqual(s.columns[0].effectiveWidth, 1)
        s.toggleFullWidth()
        XCTAssertEqual(s.columns[0].effectiveWidth, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testAdjustWidthClamps() {
        var s = strip([1])
        s.adjustWidth(by: 5)
        XCTAssertEqual(s.columns[0].width, LayoutConfig.maximumWidth)
        s.adjustWidth(by: -5)
        XCTAssertEqual(s.columns[0].width, LayoutConfig.minimumWidth)
    }

    func testHalfColumnsFillUsableWidthWithGaps() {
        let config = LayoutConfig(gap: 10, edgeGap: 20)
        let w = config.columnWidth(fraction: 0.5, viewportWidth: 1000)
        XCTAssertEqual(w * 2 + config.gap, config.usableWidth(1000), accuracy: 0.0001)
        XCTAssertEqual(config.fraction(forColumnWidth: w, viewportWidth: 1000), 0.5, accuracy: 0.0001)
    }

    func testSanitizedPresets() {
        let config = LayoutConfig(widthPresets: [0.5, 2, 0.5, 0.01, 0.3])
        XCTAssertEqual(config.sanitizedPresets, [0.1, 0.3, 0.5, 1.0])
    }

    // MARK: Scrolling and layout

    func testRevealScrollsMinimally() {
        var s = strip([1, 2, 3])  // focus on 3, offsets 0, 500, 1000
        s.revealFocused(config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 500)
        s.moveFocus(.left)
        s.revealFocused(config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 500, "column 2 is already visible")
        s.moveFocus(.left)
        s.revealFocused(config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 0)
    }

    func testRevealCentersAlways() {
        var config = flat
        config.centerMode = .always
        var s = strip([1])
        s.revealFocused(config: config, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, -250)
    }

    func testRevealOnOverflowCentersWhenScrolling() {
        var config = flat
        config.centerMode = .onOverflow
        var s = strip([1, 2, 3, 4], width: 0.25)  // 250pt columns, all fit
        s.revealFocused(config: config, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 0)
        s.insert(5, width: 0.25)  // offset 1000, off-screen
        s.revealFocused(config: config, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 250, "centring would overshoot, so it clamps to the strip end")
    }

    func testCloseTrailingGapAfterRemoval() {
        var s = strip([1, 2, 3])
        s.revealFocused(config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 500)
        s.remove(3)
        s.clampScroll(config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 0)
    }

    func testLayoutParksOffscreenColumns() {
        var s = strip([1, 2, 3])
        s.revealFocused(config: flat, viewportWidth: 1000)  // scroll 500
        let placements = s.layout(config: flat, viewport: viewport)
        XCTAssertEqual(placements.map(\.window), [1, 2, 3])
        XCTAssertTrue(placements[0].isParked)
        XCTAssertEqual(placements[0].frame.maxX, 4, "a sliver stays on screen")
        XCTAssertFalse(placements[1].isParked)
        XCTAssertEqual(placements[1].frame, Rect(x: 0, y: 0, width: 500, height: 800))
        XCTAssertEqual(placements[2].frame, Rect(x: 500, y: 0, width: 500, height: 800))
    }

    func testLayoutParksRightAndRespectsViewportOrigin() {
        let s = strip([1, 2, 3])  // scroll 0: column 3 starts at 1000
        let shifted = Rect(x: 1440, y: 25, width: 1000, height: 800)
        let placements = s.layout(config: flat, viewport: shifted)
        XCTAssertEqual(placements[0].frame.x, 1440)
        XCTAssertEqual(placements[0].frame.y, 25)
        XCTAssertTrue(placements[2].isParked)
        XCTAssertEqual(placements[2].frame.x, 2440 - 4)
    }

    func testLayoutSplitsStacksWithGaps() {
        let config = LayoutConfig(gap: 10, edgeGap: 10)
        var s = strip([1, 2])
        s.pairingArrangement = .stack
        s.consumeIntoLeft()
        let placements = s.layout(config: config, viewport: viewport)
        XCTAssertEqual(placements.count, 2)
        XCTAssertEqual(placements[0].frame.y, 10)
        XCTAssertEqual(placements[0].frame.height, 385)
        XCTAssertEqual(placements[1].frame.y, 405)
        XCTAssertEqual(placements[1].frame.maxY, 790)
    }

    func testSettleSnapsToColumnEdgeAndFocusesCentre() {
        var s = strip([1, 2, 3, 4])
        s.focusColumn(at: 0)
        s.scroll = 0
        s.scroll(by: 620, config: flat, viewportWidth: 1000)
        s.settle(config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 500)
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testScrollByIsBounded() {
        var s = strip([1, 2])
        s.scroll(by: -10_000, config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, -500)
        s.scroll(by: 10_000, config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 500)
    }

    // MARK: Pinning and tabs

    func testPinnedColumnsStayAtEdgesWhileStripScrolls() {
        var s = strip([1, 2, 3, 4], width: 0.25)  // 250pt columns
        s.focusColumn(at: 0)
        s.togglePin(.left)
        s.focusColumn(at: 3)
        s.togglePin(.right)
        s.focusColumn(at: 1)
        // Scrolling area is the middle 500pt; columns 2 and 3 fill it exactly.
        XCTAssertEqual(s.scrollArea(config: flat, viewportWidth: 1000).inset, 250)
        XCTAssertEqual(s.scrollArea(config: flat, viewportWidth: 1000).width, 500)
        s.scroll = 250  // pushes column 2 out of the scrolling area
        let placements = s.layout(config: flat, viewport: viewport)
        XCTAssertEqual(placements[0].frame.x, 0, "left-pinned column ignores scroll")
        XCTAssertEqual(placements[3].frame.x, 750, "right-pinned column ignores scroll")
        XCTAssertTrue(placements[1].isParked)
        XCTAssertEqual(placements[2].frame.x, 250)

        s.revealFocused(config: flat, viewportWidth: 1000)
        XCTAssertEqual(s.scroll, 0)
        s.focusColumn(at: 0)
        s.togglePin(.left)
        XCTAssertNil(s.columns[0].pin)
    }

    func testTabbedColumnSharesOneFrame() {
        var config = flat
        config.tabBarHeight = 30
        var s = strip([1, 2])
        s.consumeIntoLeft()
        s.toggleTabbed()
        let placements = s.layout(config: config, viewport: viewport)
        XCTAssertEqual(placements[0].frame, placements[1].frame)
        XCTAssertEqual(placements[0].frame.y, 30)
        XCTAssertEqual(placements[0].frame.height, 770)
        XCTAssertTrue(placements[0].isHiddenTab)
        XCTAssertFalse(placements[1].isHiddenTab)
        let bars = s.tabBars(config: config, viewport: viewport)
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(bars[0].windows, [1, 2])
        XCTAssertEqual(bars[0].active, 1)
    }

    // MARK: Grids and slides

    func testGridLayoutTilesTwoAcross() {
        var s = Strip()
        s.insertSlide([1, 2, 3, 4], width: 1)
        let frames = s.layout(config: flat, viewport: viewport).map(\.frame)
        XCTAssertEqual(frames[0], Rect(x: 0, y: 0, width: 500, height: 400))
        XCTAssertEqual(frames[1], Rect(x: 500, y: 0, width: 500, height: 400))
        XCTAssertEqual(frames[2], Rect(x: 0, y: 400, width: 500, height: 400))
        XCTAssertEqual(frames[3], Rect(x: 500, y: 400, width: 500, height: 400))
    }

    func testGridLoneLastTileSpansWidth() {
        var s = Strip()
        s.insertSlide([1, 2, 3], width: 1)
        let frames = s.layout(config: flat, viewport: viewport).map(\.frame)
        XCTAssertEqual(frames[2], Rect(x: 0, y: 400, width: 1000, height: 400))
        var pair = Strip()
        pair.insertSlide([1, 2], width: 1)
        XCTAssertEqual(pair.layout(config: flat, viewport: viewport).map(\.frame.height), [800, 800])
    }

    func testGridFocusMovesBetweenTilesThenSlides() {
        var s = Strip()
        s.insertSlide([1, 2, 3, 4], width: 1)
        s.insertSlide([5, 6], width: 1)
        s.focus(1)
        XCTAssertTrue(s.moveFocus(.right))
        XCTAssertEqual(s.focusedWindow, 2)
        XCTAssertTrue(s.moveFocus(.down))
        XCTAssertEqual(s.focusedWindow, 4)
        XCTAssertTrue(s.moveFocus(.right))
        XCTAssertEqual(s.focusedWindow, 5, "leaves the grid into the next slide's near tile")
        XCTAssertTrue(s.moveFocus(.left))
        XCTAssertEqual(s.focusedWindow, 4, "re-enters on the near tile of the row last used")
    }

    func testMoveWindowBetweenColumns() {
        var s = strip([1, 2, 3])
        XCTAssertTrue(s.moveWindow(3, intoColumn: 0))
        XCTAssertEqual(s.columns.map(\.windows), [[1, 3], [2]])
        XCTAssertEqual(s.focusedWindow, 3)
        s.moveWindow(1, toNewColumnAt: 2, width: 0.5)
        XCTAssertEqual(s.columns.map(\.windows), [[3], [2], [1]])
        s.moveWindow(3, toNewColumnAt: 3, width: 0.5)
        XCTAssertEqual(s.columns.map(\.windows), [[2], [1], [3]])
    }

    func testRegroupKeepsPinnedAndFocus() {
        var s = strip([1, 2, 3, 4])
        s.focusColumn(at: 0)
        s.togglePin(.left)
        s.focus(3)
        s.regroup([[2, 3], [1, 4]], width: 1)
        XCTAssertEqual(s.columns.map(\.windows), [[1], [2, 3], [4]])
        XCTAssertEqual(s.focusedWindow, 3)
        XCTAssertEqual(s.columns[1].arrangement, .grid)
    }

    func testOldColumnJSONStillDecodes() throws {
        let json = #"{"windows":[7],"active":0,"width":0.5,"isFullWidth":false}"#
        let column = try JSONDecoder().decode(Column.self, from: Data(json.utf8))
        XCTAssertEqual(column.windows, [7])
        XCTAssertEqual(column.arrangement, .stack)
        let grid = try JSONDecoder().decode(
            Column.self, from: Data(#"{"windows":[7,8],"isGrid":true}"#.utf8))
        XCTAssertEqual(grid.arrangement, .grid)
    }

    func testStackIntoRightAndPopLeft() {
        var s = strip([1, 2, 3])
        s.focus(1)
        XCTAssertTrue(s.consumeIntoRight())
        XCTAssertEqual(s.columns.map(\.windows), [[2, 1], [3]])
        XCTAssertEqual(s.focusedWindow, 1)
        XCTAssertTrue(s.expelLeft())
        XCTAssertEqual(s.columns.map(\.windows), [[1], [2], [3]])
        XCTAssertEqual(s.focusedWindow, 1)
        s.focus(3)
        XCTAssertFalse(s.consumeIntoRight())
    }

    func testJoiningASingleWindowFollowsTheSlideLayout() {
        var s = strip([1, 2])
        XCTAssertTrue(s.consumeIntoLeft())
        XCTAssertEqual(s.columns[0].arrangement, .grid, "two windows go side by side by default")
        var rows = strip([1, 2])
        rows.pairingArrangement = .stack
        rows.consumeIntoLeft()
        XCTAssertEqual(rows.columns[0].arrangement, .stack)
        // An existing multi-window layout the user chose is left as it is.
        var chosen = strip([1, 2, 3])
        chosen.focus(2)
        chosen.consumeIntoLeft()
        chosen.setArrangement(.mainTop)
        chosen.focus(3)
        chosen.consumeIntoLeft()
        XCTAssertEqual(chosen.columns[0].arrangement, .mainTop)
    }

    func testStripIsCodable() throws {
        var s = strip([1, 2, 3])
        s.consumeIntoLeft()
        s.scroll = 123
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(Strip.self, from: data), s)
    }
}
