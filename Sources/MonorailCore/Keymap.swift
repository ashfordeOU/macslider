/// Modifier keys of a shortcut. Independent of AppKit/CoreGraphics flag types.
public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)

    /// Symbols in the order macOS menus show them: ⌃⌥⇧⌘.
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A key combination. Keys are stored as physical virtual key codes, so a
/// shortcut stays on the same key whatever the keyboard layout.
public struct Shortcut: Hashable, Codable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String { modifiers.symbols + KeyCode.name(for: keyCode) }
}

/// macOS virtual key codes (`kVK_*`) for the keys Monorail uses by default.
public enum KeyCode {
    public static let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, f: UInt16 = 3, h: UInt16 = 4
    public static let g: UInt16 = 5, z: UInt16 = 6, x: UInt16 = 7, c: UInt16 = 8, v: UInt16 = 9
    public static let b: UInt16 = 11, q: UInt16 = 12, w: UInt16 = 13, e: UInt16 = 14, r: UInt16 = 15
    public static let y: UInt16 = 16, t: UInt16 = 17, o: UInt16 = 31, u: UInt16 = 32, i: UInt16 = 34
    public static let p: UInt16 = 35, l: UInt16 = 37, j: UInt16 = 38, k: UInt16 = 40, n: UInt16 = 45
    public static let m: UInt16 = 46
    public static let equal: UInt16 = 24, minus: UInt16 = 27, comma: UInt16 = 43, period: UInt16 = 47
    public static let semicolon: UInt16 = 41, grave: UInt16 = 50, zero: UInt16 = 29
    public static let slash: UInt16 = 44
    public static let rightBracket: UInt16 = 30, leftBracket: UInt16 = 33
    public static let returnKey: UInt16 = 36, tab: UInt16 = 48, space: UInt16 = 49
    public static let delete: UInt16 = 51, escape: UInt16 = 53
    public static let home: UInt16 = 115, end: UInt16 = 119, pageUp: UInt16 = 116, pageDown: UInt16 = 121
    public static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    /// Digit row 1...9.
    public static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}

/// Shortcut bindings. An action may have several shortcuts.
public struct Keymap: Equatable, Codable, Sendable {
    public var bindings: [Action: [Shortcut]]

    public init(bindings: [Action: [Shortcut]]) {
        self.bindings = bindings
    }

    public func action(for shortcut: Shortcut) -> Action? {
        for action in Action.allCases where bindings[action]?.contains(shortcut) == true {
            return action
        }
        return nil
    }

    public func shortcuts(for action: Action) -> [Shortcut] {
        bindings[action] ?? []
    }

    /// Binds `shortcut` to `action`, removing it from any other action first.
    public mutating func bind(_ shortcut: Shortcut, to action: Action, replacingIndex index: Int? = nil) {
        for key in Array(bindings.keys) {
            bindings[key]?.removeAll { $0 == shortcut }
        }
        var list = bindings[action] ?? []
        if let index, list.indices.contains(index) {
            list[index] = shortcut
        } else {
            list.append(shortcut)
        }
        bindings[action] = list
    }

    public mutating func unbind(_ action: Action, at index: Int) {
        guard bindings[action]?.indices.contains(index) == true else { return }
        bindings[action]?.remove(at: index)
    }

    /// The modifier prefixes offered in Settings. Shift is added on top for "move" actions.
    public static let prefixes: [Modifiers] = [[.control, .option], [.option], [.command, .option], [.control, .command]]

    /// Replaces `old` with `new` in every shortcut that uses exactly `old`
    /// (optionally plus Shift), keeping all other shortcuts unchanged.
    public func replacingPrefix(_ old: Modifiers, with new: Modifiers) -> Keymap {
        var result = self
        for (action, shortcuts) in bindings {
            result.bindings[action] = shortcuts.map { shortcut in
                var mods = shortcut.modifiers
                let shift = mods.contains(.shift)
                mods.remove(.shift)
                guard mods == old else { return shortcut }
                var replaced = new
                if shift { replaced.insert(.shift) }
                return Shortcut(keyCode: shortcut.keyCode, modifiers: replaced)
            }
        }
        return result
    }

    /// The prefix most shortcuts use, ignoring Shift.
    public var dominantPrefix: Modifiers {
        var counts: [Modifiers: Int] = [:]
        for shortcut in bindings.values.joined() {
            var mods = shortcut.modifiers
            mods.remove(.shift)
            counts[mods, default: 0] += 1
        }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) }?.key
            ?? [.control, .option]
    }

    /// Default shortcuts: Control-Option plus Vim keys or arrows; add Shift to move.
    public static let `default`: Keymap = {
        let co: Modifiers = [.control, .option]
        let cos: Modifiers = [.control, .option, .shift]
        let coc: Modifiers = [.control, .option, .command]
        func s(_ key: UInt16, _ mods: Modifiers) -> Shortcut { Shortcut(keyCode: key, modifiers: mods) }

        var b: [Action: [Shortcut]] = [
            .focusLeft: [s(KeyCode.h, co), s(KeyCode.left, co)],
            .focusRight: [s(KeyCode.l, co), s(KeyCode.right, co)],
            .focusUp: [s(KeyCode.k, co), s(KeyCode.up, co)],
            .focusDown: [s(KeyCode.j, co), s(KeyCode.down, co)],
            .focusFirst: [s(KeyCode.home, co)],
            .focusLast: [s(KeyCode.end, co)],
            .moveLeft: [s(KeyCode.h, cos), s(KeyCode.left, cos)],
            .moveRight: [s(KeyCode.l, cos), s(KeyCode.right, cos)],
            .moveUp: [s(KeyCode.k, cos), s(KeyCode.up, cos)],
            .moveDown: [s(KeyCode.j, cos), s(KeyCode.down, cos)],
            .cycleWidth: [s(KeyCode.r, co)],
            .cycleWidthBackward: [s(KeyCode.r, cos)],
            .narrower: [s(KeyCode.minus, co)],
            .wider: [s(KeyCode.equal, co)],
            .toggleFullWidth: [s(KeyCode.f, co)],
            .center: [s(KeyCode.c, co)],
            .consumeIntoLeft: [s(KeyCode.leftBracket, co)],
            .consumeIntoRight: [s(KeyCode.rightBracket, co)],
            .expelLeft: [s(KeyCode.leftBracket, cos)],
            .expel: [s(KeyCode.rightBracket, cos)],
            .toggleFloat: [s(KeyCode.t, co)],
            .pinLeft: [s(KeyCode.p, co)],
            .pinRight: [s(KeyCode.p, cos)],
            .toggleTabbed: [s(KeyCode.w, co), s(KeyCode.t, cos)],
            .cycleLayout: [s(KeyCode.g, co)],
            .mainLarger: [s(KeyCode.period, co)],
            .mainSmaller: [s(KeyCode.comma, co)],
            .makeMain: [s(KeyCode.m, co)],
            .regroup: [s(KeyCode.a, co)],
            .overview: [s(KeyCode.o, co), s(KeyCode.tab, co)],
            .toggleNativeFullScreen: [s(KeyCode.f, cos)],
            .windowSwitcher: [s(KeyCode.space, co)],
            .sendToNextDisplay: [s(KeyCode.d, co), s(KeyCode.n, co)],
            .retile: [s(KeyCode.escape, co)],
            .undo: [s(KeyCode.z, co)],
            .setMark: [s(KeyCode.semicolon, cos)],
            .jumpToMark: [s(KeyCode.semicolon, co)],
            .toggleScratchpad: [s(KeyCode.grave, co)],
            .makeScratchpad: [s(KeyCode.grave, cos)],
            .nextProfile: [s(KeyCode.zero, co)],
            .toggleFocusMode: [s(KeyCode.b, co)],
            .commandPalette: [s(KeyCode.slash, co)],
            .takeSnapshot: [s(KeyCode.s, cos)],
            .toggleSticky: [s(KeyCode.s, co)],
            .zoomTile: [s(KeyCode.x, co)],
            .lastWindow: [s(KeyCode.delete, co)],
            .quickLaunch: [s(KeyCode.u, co)],
            .pictureInPicture: [s(KeyCode.i, co)],
            .radialMenu: [s(KeyCode.e, co)],
            .balanceSizes: [s(KeyCode.equal, cos)],
            .workspaceBackAndForth: [s(KeyCode.delete, cos)],
            .moveToEmptyWorkspace: [s(KeyCode.n, cos)],
            .focusAttention: [s(KeyCode.a, cos)],
            .showDesktop: [s(KeyCode.d, cos)],
            .screenshotSlide: [s(KeyCode.c, cos)],
            .appOverview: [s(KeyCode.o, cos)],
            .windowHints: [s(KeyCode.v, co)],
            .resizeMode: [s(KeyCode.e, cos)],
            .stripZoom: [s(KeyCode.z, cos)],
            .presentationMode: [s(KeyCode.y, cos)],
            .recordSlide: [s(KeyCode.v, cos)],
            // Snapping (floats the window first): Control-Option-Command plus a key.
            .snapLeftHalf: [s(KeyCode.left, coc)],
            .snapRightHalf: [s(KeyCode.right, coc)],
            .snapTopHalf: [s(KeyCode.up, coc)],
            .snapBottomHalf: [s(KeyCode.down, coc)],
            .snapFirstThird: [s(KeyCode.d, coc)],
            .snapCenterThird: [s(KeyCode.f, coc)],
            .snapLastThird: [s(KeyCode.g, coc)],
            .snapFirstTwoThirds: [s(KeyCode.e, coc)],
            .snapLastTwoThirds: [s(KeyCode.t, coc)],
            .snapTopLeft: [s(KeyCode.u, coc)],
            .snapTopRight: [s(KeyCode.i, coc)],
            .snapBottomLeft: [s(KeyCode.j, coc)],
            .snapBottomRight: [s(KeyCode.k, coc)],
            .snapMaximize: [s(KeyCode.returnKey, coc)],
            .snapCenter: [s(KeyCode.c, coc)],
            .snapRestore: [s(KeyCode.delete, coc)],
            .togglePause: [s(KeyCode.q, co)],
        ]
        // Digits switch workspaces (add Shift to take the window along).
        // Jumping to a column by number is in slide mode, or can be bound in Settings.
        for action in Action.allCases {
            if let n = action.workspaceNumber { b[action] = [s(KeyCode.digits[n - 1], co)] }
            if let n = action.moveToWorkspaceNumber { b[action] = [s(KeyCode.digits[n - 1], cos)] }
        }
        return Keymap(bindings: b)
    }()
}

extension Keymap {
    // Encoded as { "action-name": [shortcut, ...] } so the file stays readable
    // and unknown actions from newer versions are ignored instead of failing.
    private struct ActionKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ActionKey.self)
        var bindings: [Action: [Shortcut]] = [:]
        for key in container.allKeys {
            guard let action = Action(rawValue: key.stringValue) else { continue }
            bindings[action] = try container.decode([Shortcut].self, forKey: key)
        }
        self.bindings = bindings
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ActionKey.self)
        for action in Action.allCases {
            if let list = bindings[action] {
                try container.encode(list, forKey: ActionKey(stringValue: action.rawValue))
            }
        }
    }
}
