import Foundation
import XCTest
@testable import MonorailCore

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

    func testResizingATileMovesTheSplit() {
        var pair = slide([1, 2], .columns)
        XCTAssertTrue(pair.resizeTile(2, toFraction: (0.3, 1)))
        XCTAssertEqual(pair.columns[0].arrangement, .mainLeft)
        XCTAssertEqual(pair.columns[0].split, 0.7, accuracy: 0.0001)
        XCTAssertTrue(pair.columns[0].isCustom)

        var main = slide([1, 2, 3], .mainTop)
        XCTAssertTrue(main.resizeTile(1, toFraction: (1, 0.9)))
        XCTAssertEqual(main.columns[0].split, Arrangement.splitRange.upperBound, "clamped")

        var grid = slide([1, 2, 3, 4], .grid)
        XCTAssertFalse(grid.resizeTile(1, toFraction: (0.4, 0.5)), "a 2×2 grid has no single split")
    }

    func testMoveOthersOut() {
        var strip = slide([1, 2, 3], .mainLeft)
        XCTAssertTrue(strip.moveOthersOut(keeping: 2))
        XCTAssertEqual(strip.columns.map(\.windows), [[2], [1, 3]])
        XCTAssertEqual(strip.focusedWindow, 2)
        XCTAssertFalse(strip.moveOthersOut(keeping: 2))
    }

    func testCustomLayouts() {
        // [1, 2]: one tall tile beside two stacked.
        XCTAssertEqual(Arrangement.customFrames(count: 3, rows: [1, 2]), [
            Rect(x: 0, y: 0, width: 0.5, height: 1), Rect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            Rect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
        // Fewer windows than cells: the last cells are left out.
        XCTAssertEqual(Arrangement.customFrames(count: 2, rows: [1, 2]).count, 2)
        XCTAssertEqual(Arrangement.customFrames(count: 2, rows: [1, 2])[1], Rect(x: 0.5, y: 0, width: 0.5, height: 1))
        // More windows than cells: the last column takes them.
        XCTAssertEqual(Arrangement.customFrames(count: 4, rows: [1, 2]).last, Rect(x: 0.5, y: 2.0 / 3.0, width: 0.5, height: 1.0 / 3.0))

        var strip = slide([1, 2, 3], .grid)
        strip.setArrangement(.custom, rows: [2, 1])
        XCTAssertEqual(strip.columns[0].customRows, [2, 1])
        strip.focus(3)
        XCTAssertTrue(strip.moveFocus(.left))
        XCTAssertEqual(strip.focusedWindow, 1, "navigation follows the custom cells")
        strip.setArrangement(.grid)
        XCTAssertNil(strip.columns[0].customRows)
    }
}

final class SwapTilesTests: XCTestCase {
    func testSwapTilesExchangesPlacesAndKeepsFocus() {
        var strip = Strip()
        strip.insertSlide([1, 2, 3], width: 1, arrangement: .mainLeft)
        strip.focus(1)
        XCTAssertTrue(strip.swapTiles(1, 3))
        XCTAssertEqual(strip.columns[0].windows, [3, 2, 1])
        XCTAssertEqual(strip.focusedWindow, 1)
        XCTAssertTrue(strip.columns[0].isCustom)
    }

    func testSwapTilesNeedsSameSlide() {
        var strip = Strip()
        strip.insertSlide([1, 2], width: 1)
        strip.insertSlide([3], width: 1)
        XCTAssertFalse(strip.swapTiles(1, 3))
        XCTAssertFalse(strip.swapTiles(1, 1))
    }

    func testInsertSlideKeepsCustomRows() {
        var strip = Strip()
        strip.insertSlide([1, 2, 3], width: 1, arrangement: .custom, custom: true, rows: [1, 2])
        XCTAssertEqual(strip.columns[0].customRows, [1, 2])
        XCTAssertTrue(strip.columns[0].isCustom)
        XCTAssertEqual(strip.columns[0].unitFrames[0], Rect(x: 0, y: 0, width: 0.5, height: 1))
    }
}

final class SettingsV6Tests: XCTestCase {
    func testTitleRuleWinsOverAppRule() {
        var settings = AppSettings()
        settings.appRules = [
            AppRule(bundleID: "com.google.Chrome", name: "Chrome", width: 0.5),
            AppRule(bundleID: "com.google.Chrome", name: "Chrome", float: true, titleContains: "Meet"),
        ]
        XCTAssertEqual(settings.rule(for: "com.google.Chrome", title: "Google Meet - call")?.float, true)
        XCTAssertEqual(settings.rule(for: "com.google.Chrome", title: "Inbox")?.width, 0.5)
        XCTAssertEqual(settings.rule(for: "com.google.Chrome")?.float, false)
        XCTAssertNotEqual(settings.appRules[0].id, settings.appRules[1].id)
    }

    func testDisplayOverride() {
        var settings = AppSettings()
        settings.layout.gap = 10
        settings.displayOverrides["A"] = DisplayOverride(name: "Studio", gap: 24, sliderBar: .off)
        XCTAssertEqual(settings.layout(for: "A").gap, 24)
        XCTAssertEqual(settings.layout(for: "B").gap, 10)
        XCTAssertEqual(settings.sliderBar(for: "A"), .off)
        XCTAssertEqual(settings.sliderBar(for: "B"), settings.sliderBar)
    }

    func testNewActionsGetDefaultKeysAfterUpdate() throws {
        var old = AppSettings()
        old.keymap.bindings[.commandPalette] = nil
        old.keymap.bindings[.toggleFocusMode] = nil
        let data = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.keymap.shortcuts(for: .commandPalette), Keymap.default.shortcuts(for: .commandPalette))
        XCTAssertFalse(decoded.keymap.shortcuts(for: .toggleFocusMode).isEmpty)
    }

    func testSmartGaps() {
        var settings = AppSettings()
        settings.layout.gap = 10
        settings.layout.edgeGap = 8
        XCTAssertEqual(settings.layout(for: "A", displayWidth: 3000, windowCount: 1).gap, 10, "off by default")
        settings.smartGaps = true
        XCTAssertEqual(settings.layout(for: "A", displayWidth: 1440, windowCount: 1).gap, 0)
        XCTAssertEqual(settings.layout(for: "A", displayWidth: 1440, windowCount: 1).edgeGap, 0)
        XCTAssertEqual(settings.layout(for: "A", displayWidth: 3000, windowCount: 3).gap, 15)
        XCTAssertEqual(settings.layout(for: "A", displayWidth: 1440, windowCount: 3).gap, 10)
    }

    func testAutoRuleTiming() {
        let weekdays = AutoRule(name: "Work", trigger: .time, minuteOfDay: 9 * 60, weekdays: [2, 3, 4, 5, 6])
        XCTAssertTrue(weekdays.isDue(minuteOfDay: 540, weekday: 2))
        XCTAssertFalse(weekdays.isDue(minuteOfDay: 540, weekday: 1))
        XCTAssertFalse(weekdays.isDue(minuteOfDay: 541, weekday: 2))
        var off = weekdays
        off.isEnabled = false
        XCTAssertFalse(off.isDue(minuteOfDay: 540, weekday: 2))
        XCTAssertTrue(AutoRule(name: "Daily", trigger: .time, minuteOfDay: 60).isDue(minuteOfDay: 60, weekday: 7))
    }
}

final class LayoutsV7Tests: XCTestCase {
    func testAccordionOverlapsWithEveryEdgeShowing() {
        let frames = Arrangement.accordion.unitFrames(count: 3)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].minX, 0, accuracy: 1e-9)
        XCTAssertEqual(frames[2].maxX, 1, accuracy: 1e-9)
        XCTAssertEqual(frames[1].minX - frames[0].minX, Arrangement.accordionStep, accuracy: 1e-9)
        XCTAssertTrue(frames.allSatisfy { $0.height == 1 })
    }

    func testSpiralFillsTheSlideWithoutOverlap() {
        for count in 2...6 {
            let frames = Arrangement.spiral.unitFrames(count: count)
            XCTAssertEqual(frames.count, count)
            let area = frames.reduce(0.0) { $0 + $1.width * $1.height }
            XCTAssertEqual(area, 1, accuracy: 1e-9, "\(count) windows cover the slide")
            for i in frames.indices {
                for j in frames.indices where j > i {
                    let a = frames[i], b = frames[j]
                    let overlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) * max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
                    XCTAssertEqual(overlap, 0, accuracy: 1e-9)
                }
            }
        }
        XCTAssertEqual(Arrangement.spiral.unitFrames(count: 2, split: 0.6)[0].width, 0.6, accuracy: 1e-9)
    }

    func testBalanceEvensOutTheStrip() {
        var strip = Strip()
        strip.insertSlide([1, 2], width: 0.8, arrangement: .mainLeft)
        strip.insert(3, width: 0.3, position: .end, focus: false)
        strip.toggleFullWidth()
        strip.balance(width: 0.5)
        XCTAssertTrue(strip.columns.allSatisfy { $0.width == 0.5 && !$0.isFullWidth && $0.split == Arrangement.defaultSplit })
    }

    func testCyclingVisitsTheNewLayouts() {
        var seen: Set<Arrangement> = []
        var arrangement = Arrangement.grid
        for _ in 0..<10 {
            seen.insert(arrangement)
            arrangement = arrangement.next
        }
        XCTAssertTrue(seen.isSuperset(of: [.spiral, .accordion]))
    }
}
