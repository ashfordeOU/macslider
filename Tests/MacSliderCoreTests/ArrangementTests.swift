import Foundation
import XCTest
@testable import MacSliderCore

final class ArrangementTests: XCTestCase {
    let flat = LayoutConfig(gap: 0, edgeGap: 0)
    let viewport = Rect(x: 0, y: 0, width: 1200, height: 600)

    private func slide(_ ids: [WindowID], _ arrangement: Arrangement) -> Strip {
        var strip = Strip()
        strip.insertSlide(ids, width: 1, arrangement: arrangement)
        return strip
    }

    func testGridGrowsWithCount() {
        XCTAssertEqual(Arrangement.gridColumns(for: 4), 2)
        XCTAssertEqual(Arrangement.gridColumns(for: 5), 3)
        XCTAssertEqual(Arrangement.gridColumns(for: 9), 3)
        // Five tiles: three on top, two stretched below.
        let frames = slide([1, 2, 3, 4, 5], .grid).layout(config: flat, viewport: viewport).map(\.frame)
        XCTAssertEqual(frames[0], Rect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(frames[2], Rect(x: 800, y: 0, width: 400, height: 300))
        XCTAssertEqual(frames[3], Rect(x: 0, y: 300, width: 600, height: 300))
        XCTAssertEqual(frames[4], Rect(x: 600, y: 300, width: 600, height: 300))
    }

    func testMainLeftAndSplit() {
        var strip = slide([1, 2, 3], .mainLeft)
        var frames = strip.layout(config: flat, viewport: viewport).map(\.frame)
        XCTAssertEqual(frames[0], Rect(x: 0, y: 0, width: 720, height: 600))
        XCTAssertEqual(frames[1], Rect(x: 720, y: 0, width: 480, height: 300))
        XCTAssertEqual(frames[2], Rect(x: 720, y: 300, width: 480, height: 300))
        strip.adjustSplit(by: 1)
        XCTAssertEqual(strip.columns[0].split, Arrangement.splitRange.upperBound)
        frames = strip.layout(config: flat, viewport: viewport).map(\.frame)
        XCTAssertEqual(frames[0].width, 960)
    }

    func testMainTopAndColumns() {
        let top = slide([1, 2, 3], .mainTop).layout(config: flat, viewport: viewport).map(\.frame)
        XCTAssertEqual(top[0], Rect(x: 0, y: 0, width: 1200, height: 360))
        XCTAssertEqual(top[2], Rect(x: 600, y: 360, width: 600, height: 240))
        let columns = slide([1, 2, 3], .columns).layout(config: flat, viewport: viewport).map(\.frame)
        XCTAssertEqual(columns.map(\.x), [0, 400, 800])
    }

    func testGapsOnlyBetweenTiles() {
        let config = LayoutConfig(gap: 10, edgeGap: 0)
        let frames = slide([1, 2], .columns).layout(config: config, viewport: viewport).map(\.frame)
        XCTAssertEqual(frames[0], Rect(x: 0, y: 0, width: 595, height: 600))
        XCTAssertEqual(frames[1], Rect(x: 605, y: 0, width: 595, height: 600))
    }

    func testNavigationFollowsPositions() {
        var strip = slide([1, 2, 3], .mainLeft)
        strip.focus(1)
        XCTAssertTrue(strip.moveFocus(.right))
        XCTAssertEqual(strip.focusedWindow, 2)
        XCTAssertTrue(strip.moveFocus(.down))
        XCTAssertEqual(strip.focusedWindow, 3)
        XCTAssertTrue(strip.moveFocus(.left))
        XCTAssertEqual(strip.focusedWindow, 1)
        XCTAssertFalse(strip.moveFocus(.up))
    }

    func testMoveSwapsTilesBeforeColumns() {
        var strip = slide([1, 2], .columns)
        strip.focus(1)
        XCTAssertTrue(strip.moveFocused(.right))
        XCTAssertEqual(strip.columns[0].windows, [2, 1])
        XCTAssertFalse(strip.moveFocused(.right), "already at the strip's right end")
    }

    func testCycleAndPromote() {
        var strip = slide([1, 2, 3], .grid)
        strip.cycleArrangement()
        XCTAssertEqual(strip.columns[0].arrangement, .columns)
        strip.toggleTabbed()
        strip.cycleArrangement()
        XCTAssertFalse(strip.columns[0].isTabbed, "cycling leaves tabs first")
        XCTAssertEqual(strip.columns[0].arrangement, .columns)
        strip.focus(3)
        strip.promoteToMain()
        XCTAssertEqual(strip.columns[0].windows, [3, 1, 2])
        XCTAssertEqual(strip.focusedWindow, 3)
    }

    func testRightToLeftMirrorsTheStrip() {
        var config = flat
        config.direction = .rightToLeft
        var strip = Strip()
        strip.insert(1, width: 0.5)
        strip.insert(2, width: 0.5)
        strip.insert(3, width: 0.5)
        strip.focus(1)
        strip.revealFocused(config: config, viewportWidth: viewport.width)
        let frames = strip.layout(config: config, viewport: viewport)
        XCTAssertEqual(frames[0].frame.x, 600, "the first column sits at the right edge")
        XCTAssertEqual(frames[1].frame.x, 0)
        XCTAssertTrue(frames[2].isParked)
        XCTAssertEqual(frames[2].frame.maxX, 4, "parked off the left edge")

        var main = slide([1, 2], .mainLeft)
        main.focus(1)
        let tiles = main.layout(config: config, viewport: viewport).map(\.frame)
        XCTAssertEqual(tiles[0].x, 480, "the main tile is mirrored to the right")
    }
}
