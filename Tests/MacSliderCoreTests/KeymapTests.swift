import Foundation
import XCTest
@testable import MacSliderCore

final class KeymapTests: XCTestCase {
    func testDefaultKeymapHasNoDuplicateShortcuts() {
        var seen: [Shortcut: Action] = [:]
        for (action, shortcuts) in Keymap.default.bindings {
            for shortcut in shortcuts {
                XCTAssertNil(seen[shortcut], "\(shortcut.displayString) bound to \(action) and \(seen[shortcut]!)")
                seen[shortcut] = action
            }
        }
    }

    func testEveryActionHasADefaultShortcut() {
        for action in Action.allCases {
            XCTAssertFalse(Keymap.default.shortcuts(for: action).isEmpty, "\(action) has no default")
        }
    }

    func testLookup() {
        let shortcut = Shortcut(keyCode: KeyCode.l, modifiers: [.control, .option])
        XCTAssertEqual(Keymap.default.action(for: shortcut), .focusRight)
        XCTAssertNil(Keymap.default.action(for: Shortcut(keyCode: KeyCode.l, modifiers: [.command])))
    }

    func testBindMovesShortcutBetweenActions() {
        var keymap = Keymap.default
        let shortcut = Shortcut(keyCode: KeyCode.l, modifiers: [.control, .option])
        keymap.bind(shortcut, to: .center)
        XCTAssertEqual(keymap.action(for: shortcut), .center)
        XCTAssertFalse(keymap.shortcuts(for: .focusRight).contains(shortcut))
    }

    func testBindReplacingIndex() {
        var keymap = Keymap.default
        let shortcut = Shortcut(keyCode: KeyCode.g, modifiers: [.control])
        keymap.bind(shortcut, to: .center, replacingIndex: 0)
        XCTAssertEqual(keymap.shortcuts(for: .center), [shortcut])
        keymap.unbind(.center, at: 0)
        XCTAssertTrue(keymap.shortcuts(for: .center).isEmpty)
    }

    func testDisplayString() {
        let shortcut = Shortcut(keyCode: KeyCode.left, modifiers: [.shift, .control, .option])
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧←")
    }

    func testActionFromURL() {
        XCTAssertEqual(Action(url: "macslider://focus-left"), .focusLeft)
        XCTAssertEqual(Action(url: "macslider://Center/"), .center)
        XCTAssertEqual(Action(url: "toggle-pause"), .togglePause)
        XCTAssertNil(Action(url: "macslider://nope"))
        XCTAssertEqual(Action.focusColumn7.columnNumber, 7)
        XCTAssertEqual(Action.focusColumn7.title, "Focus column 7")
    }

    func testReplacingPrefixKeepsShift() {
        let keymap = Keymap.default.replacingPrefix([.control, .option], with: [.command, .option])
        XCTAssertEqual(
            keymap.action(for: Shortcut(keyCode: KeyCode.l, modifiers: [.command, .option])), .focusRight)
        XCTAssertEqual(
            keymap.action(for: Shortcut(keyCode: KeyCode.l, modifiers: [.command, .option, .shift])), .moveRight)
        XCTAssertNil(keymap.action(for: Shortcut(keyCode: KeyCode.l, modifiers: [.control, .option])))
        XCTAssertEqual(keymap.dominantPrefix, [.command, .option])
        XCTAssertEqual(Keymap.default.dominantPrefix, [.control, .option])
    }

    func testAppRuleLookup() {
        let settings = AppSettings()
        XCTAssertEqual(settings.rule(for: "com.apple.calculator")?.float, true)
        XCTAssertNil(settings.rule(for: "com.example.none"))
        XCTAssertNil(settings.rule(for: nil))
    }

    func testSlideModeKeys() {
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.right, modifiers: []), .action(.focusRight))
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.h, modifiers: []), .action(.focusLeft))
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.left, modifiers: [.shift]), .action(.moveLeft))
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.r, modifiers: []), .action(.cycleWidth))
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.digits[2], modifiers: []), .action(.focusColumn3))
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.escape, modifiers: []), .exit)
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.returnKey, modifiers: []), .exit)
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.x, modifiers: []), .passThrough)
        XCTAssertEqual(SlideMode.resolve(keyCode: KeyCode.c, modifiers: [.command]), .passThrough)
    }

    func testSlideTriggers() {
        XCTAssertNil(SlideTrigger.off.keyCode)
        XCTAssertEqual(SlideTrigger.rightOption.keyCode, 61)
        XCTAssertEqual(AppSettings().slideTrigger, .rightOption)
        XCTAssertEqual(AppSettings().scrollModifier, [.option])
    }

    func testSettingsRoundTripAndTolerantDecoding() throws {
        var settings = AppSettings()
        settings.layout.gap = 3
        settings.keymap.unbind(.center, at: 0)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)

        let partial = #"{"animate": false, "layout": {"gap": 2}, "keymap": {"bogus": []}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(partial.utf8))
        XCTAssertFalse(decoded.animate)
        XCTAssertEqual(decoded.layout.gap, 2)
        XCTAssertEqual(decoded.layout.edgeGap, LayoutConfig().edgeGap)
        XCTAssertTrue(decoded.keymap.bindings.isEmpty)
    }
}
