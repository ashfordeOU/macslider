import Foundation
import XCTest
@testable import MonorailCore

final class SavedLayoutTests: XCTestCase {
    private func fp(_ app: String, _ title: String) -> WindowFingerprint { WindowFingerprint(app: app, title: title) }

    func testMatcherPrefersExactTitlesThenSameApp() {
        var strip = Strip()
        strip.insertSlide([1, 2], width: 1, arrangement: .mainLeft)
        strip.insertSlide([3], width: 1)
        let prints: [WindowID: WindowFingerprint] = [1: fp("safari", "Docs"), 2: fp("safari", "Mail"), 3: fp("notes", "Ideas")]
        let saved = strip.columns.map { SavedColumn($0, fingerprint: { prints[$0] }) }

        // After a restart: new IDs, one Safari title changed.
        let now: [(id: WindowID, fingerprint: WindowFingerprint)] = [
            (11, fp("safari", "Inbox")), (12, fp("safari", "Docs")), (13, fp("notes", "Ideas")), (14, fp("music", "x")),
        ]
        var used = Set<WindowID>()
        let columns = LayoutMatcher.columns(for: saved, windows: now, used: &used)
        XCTAssertEqual(columns.map(\.windows), [[12, 11], [13]])
        XCTAssertEqual(columns[0].arrangement, .mainLeft)
        XCTAssertEqual(used, [11, 12, 13])
    }

    func testMatcherDropsColumnsWithNoWindows() {
        let saved = [SavedColumn(Column(windows: [1], width: 1), fingerprint: { _ in WindowFingerprint(app: "gone", title: "") })]
        var used = Set<WindowID>()
        XCTAssertTrue(LayoutMatcher.columns(for: saved, windows: [(2, fp("other", ""))], used: &used).isEmpty)
    }

    func testSavedLayoutRoundTrips() throws {
        let layout = SavedLayout(name: "Coding", workspaces: [0: [SavedColumn(Column(windows: [1], width: 0.5), fingerprint: { _ in WindowFingerprint(app: "a", title: "b") })]])
        let data = try JSONEncoder().encode(layout)
        XCTAssertEqual(try JSONDecoder().decode(SavedLayout.self, from: data), layout)
        XCTAssertEqual(layout.windowCount, 1)
    }

    func testSnapFrames() {
        let area = Rect(x: 0, y: 25, width: 1000, height: 800)
        XCTAssertEqual(SnapPosition.leftHalf.frame(in: area, gap: 0), Rect(x: 0, y: 25, width: 500, height: 800))
        XCTAssertEqual(SnapPosition.bottomRight.frame(in: area, gap: 0), Rect(x: 500, y: 425, width: 500, height: 400))
        let gapped = SnapPosition.rightHalf.frame(in: area, gap: 10)
        XCTAssertEqual(gapped.x, 505)
        XCTAssertEqual(gapped.maxX, 990)
    }
}
