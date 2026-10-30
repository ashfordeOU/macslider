import Foundation
import XCTest
@testable import MacSliderCore

final class GroupingTests: XCTestCase {
    // Windows 1-3 Safari, 4 Notes, 5 Mail, 6 Music, 10-14 Terminal.
    private func app(_ id: WindowID) -> String {
        switch id {
        case 1...3: return "safari"
        case 4: return "notes"
        case 5: return "mail"
        case 6: return "music"
        default: return "terminal"
        }
    }

    private func capacity(_ app: String) -> Int { app == "terminal" ? 4 : 2 }

    func testPlanGroupsByAppAndPairsSingles() {
        let groups = Grouping.plan([1, 4, 2, 5, 3, 6, 10, 11, 12, 13, 14], app: app, capacity: capacity)
        XCTAssertEqual(groups, [[1, 2], [3], [4, 5], [6], [10, 11, 12, 13], [14]])
    }

    func testPlanWithOnlySingles() {
        XCTAssertEqual(Grouping.plan([4, 5, 6], app: app, capacity: capacity), [[4, 5], [6]])
    }

    func testDecideJoinsSameAppSlideWithRoom() {
        var strip = Strip()
        strip.insertSlide([1], width: 1)
        strip.insertSlide([10, 11], width: 1)
        strip.insertSlide([4], width: 1)
        let decision = Grouping.decide(newApp: "terminal", strip: strip, app: app, capacity: capacity)
        XCTAssertEqual(decision, .join(column: 1))
    }

    func testDecidePairsLoneWindows() {
        var strip = Strip()
        strip.insertSlide([4], width: 1)
        XCTAssertEqual(Grouping.decide(newApp: "mail", strip: strip, app: app, capacity: capacity), .join(column: 0))
        strip.add(5, toColumn: 0)
        XCTAssertEqual(Grouping.decide(newApp: "music", strip: strip, app: app, capacity: capacity), .newSlide)
    }

    func testDecideSecondWindowPullsFirstOutOfSharedSlide() {
        var strip = Strip()
        strip.insertSlide([1, 4], width: 1)  // Safari sharing with Notes
        XCTAssertEqual(
            Grouping.decide(newApp: "safari", strip: strip, app: app, capacity: capacity), .pairWith(window: 1))
    }

    func testDecideSecondWindowJoinsLoneSameAppSlide() {
        var strip = Strip()
        strip.insertSlide([1], width: 1)
        XCTAssertEqual(Grouping.decide(newApp: "safari", strip: strip, app: app, capacity: capacity), .join(column: 0))
    }

    func testFullSlideStartsANewOne() {
        var strip = Strip()
        strip.insertSlide([1, 2], width: 1)
        XCTAssertEqual(Grouping.decide(newApp: "safari", strip: strip, app: app, capacity: capacity), .newSlide)
    }

    func testLoneWindowsStayApartUnlessAsked() {
        var strip = Strip()
        strip.insertSlide([4], width: 1)
        XCTAssertEqual(
            Grouping.decide(newApp: "mail", strip: strip, app: app, capacity: capacity, pairLoneWindows: false),
            .newSlide)
    }

    func testRestoreIntoOldColumn() {
        var strip = Strip()
        strip.insertSlide([1, 2], width: 1)
        strip.insertSlide([4], width: 1)
        let slot = strip.slot(of: 1)!
        strip.remove(1)
        strip.restore(1, to: slot)
        XCTAssertEqual(strip.columns.map(\.windows), [[1, 2], [4]])
        XCTAssertEqual(strip.focusedWindow, 1)
    }

    func testRestoreAsColumnAtOldIndex() {
        var strip = Strip()
        strip.insertSlide([4], width: 1)
        strip.insertSlide([1], width: 1, arrangement: .mainLeft)
        strip.insertSlide([5], width: 1)
        let slot = strip.slot(of: 1)!
        strip.remove(1)
        strip.focus(4)
        strip.restore(1, to: slot, focus: false)
        XCTAssertEqual(strip.columns.map(\.windows), [[4], [1], [5]])
        XCTAssertEqual(strip.columns[1].arrangement, .mainLeft)
        XCTAssertEqual(strip.focusedWindow, 4)
    }

    func testCustomPairsAreLeftAlone() {
        var strip = Strip()
        strip.insertSlide([1], width: 1)  // Safari
        strip.insertSlide([4], width: 1)  // Notes
        strip.focus(4)
        XCTAssertTrue(strip.consumeIntoLeft())  // the user pairs Notes with Safari
        XCTAssertTrue(strip.columns[0].isCustom)
        // A second Safari window doesn't pull the first out of the user's pair...
        XCTAssertEqual(Grouping.decide(newApp: "safari", strip: strip, app: app, capacity: capacity), .newSlide)
        // ...and a lone window doesn't join it either.
        XCTAssertEqual(Grouping.decide(newApp: "mail", strip: strip, app: app, capacity: capacity), .newSlide)
        // Resetting to smart pairs clears the mark.
        strip.regroup([[1], [4]], width: 1)
        XCTAssertFalse(strip.columns.contains(where: \.isCustom))
    }

    func testSlidesHoldAtMostSixWindows() {
        var strip = Strip()
        strip.insertSlide([1, 2, 3, 4, 5, 6], width: 1)
        XCTAssertTrue(strip.columns[0].isFull)
        strip.add(7, toColumn: 0)
        XCTAssertEqual(strip.columns.map(\.windows), [[1, 2, 3, 4, 5, 6], [7]], "a full slide spills into a new one")
        XCTAssertFalse(strip.consumeIntoLeft(), "can't stack into a full slide")
        XCTAssertFalse(strip.moveWindow(7, intoColumn: 0))
        let plan = Grouping.plan(Array(10...17), app: app, capacity: { _ in 9 })
        XCTAssertEqual(plan.map(\.count), [6, 2])
        XCTAssertEqual(AppSettings().tiles(for: "com.apple.Terminal"), 4)
    }
}
