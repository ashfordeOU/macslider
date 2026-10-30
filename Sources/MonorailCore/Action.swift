/// Everything Monorail can do from a shortcut or a `monorail://` URL.
/// Raw values are stable: they are stored in the config file and used as URL hosts.
public enum Action: String, Codable, CaseIterable, Sendable {
    case focusLeft = "focus-left"
    case focusRight = "focus-right"
    case focusUp = "focus-up"
    case focusDown = "focus-down"
    case focusFirst = "focus-first"
    case focusLast = "focus-last"
    case focusColumn1 = "focus-column-1"
    case focusColumn2 = "focus-column-2"
    case focusColumn3 = "focus-column-3"
    case focusColumn4 = "focus-column-4"
    case focusColumn5 = "focus-column-5"
    case focusColumn6 = "focus-column-6"
    case focusColumn7 = "focus-column-7"
    case focusColumn8 = "focus-column-8"
    case focusColumn9 = "focus-column-9"
    case moveLeft = "move-left"
    case moveRight = "move-right"
    case moveUp = "move-up"
    case moveDown = "move-down"
    case cycleWidth = "cycle-width"
    case cycleWidthBackward = "cycle-width-backward"
    case narrower
    case wider
    case toggleFullWidth = "full-width"
    case center
    case consumeIntoLeft = "stack-into-left"
    case consumeIntoRight = "stack-into-right"
    case expelLeft = "unstack-left"
    case expel = "unstack"
    case toggleFloat = "toggle-float"
    case pinLeft = "pin-left"
    case pinRight = "pin-right"
    case toggleTabbed = "toggle-tabbed"
    case cycleLayout = "cycle-layout"
    case mainLarger = "main-larger"
    case mainSmaller = "main-smaller"
    case makeMain = "make-main"
    case regroup
    case overview
    case toggleNativeFullScreen = "toggle-fullscreen"
    case windowSwitcher = "window-switcher"
    case sendToNextDisplay = "send-to-next-display"
    case workspace1 = "workspace-1"
    case workspace2 = "workspace-2"
    case workspace3 = "workspace-3"
    case workspace4 = "workspace-4"
    case workspace5 = "workspace-5"
    case workspace6 = "workspace-6"
    case workspace7 = "workspace-7"
    case workspace8 = "workspace-8"
    case workspace9 = "workspace-9"
    case moveToWorkspace1 = "move-to-workspace-1"
    case moveToWorkspace2 = "move-to-workspace-2"
    case moveToWorkspace3 = "move-to-workspace-3"
    case moveToWorkspace4 = "move-to-workspace-4"
    case moveToWorkspace5 = "move-to-workspace-5"
    case moveToWorkspace6 = "move-to-workspace-6"
    case moveToWorkspace7 = "move-to-workspace-7"
    case moveToWorkspace8 = "move-to-workspace-8"
    case moveToWorkspace9 = "move-to-workspace-9"
    case snapLeftHalf = "snap-left-half"
    case snapRightHalf = "snap-right-half"
    case snapTopHalf = "snap-top-half"
    case snapBottomHalf = "snap-bottom-half"
    case snapFirstThird = "snap-first-third"
    case snapCenterThird = "snap-center-third"
    case snapLastThird = "snap-last-third"
    case snapFirstTwoThirds = "snap-first-two-thirds"
    case snapLastTwoThirds = "snap-last-two-thirds"
    case snapTopLeft = "snap-top-left"
    case snapTopRight = "snap-top-right"
    case snapBottomLeft = "snap-bottom-left"
    case snapBottomRight = "snap-bottom-right"
    case snapMaximize = "snap-maximize"
    case snapCenter = "snap-center"
    case snapRestore = "snap-restore"
    case setMark = "set-mark"
    case jumpToMark = "jump-to-mark"
    case toggleScratchpad = "scratchpad"
    case makeScratchpad = "make-scratchpad"
    case nextProfile = "next-profile"
    case toggleFocusMode = "focus-mode"
    case commandPalette = "command-palette"
    case takeSnapshot = "snapshot"
    case toggleSticky = "sticky"
    case zoomTile = "zoom"
    case lastWindow = "last-window"
    case quickLaunch = "launch"
    case pictureInPicture = "picture-in-picture"
    case retile
    case undo
    case togglePause = "toggle-pause"

    public var title: String {
        switch self {
        case .focusLeft: return "Focus left"
        case .focusRight: return "Focus right"
        case .focusUp: return "Focus up in stack"
        case .focusDown: return "Focus down in stack"
        case .focusFirst: return "Focus first column"
        case .focusLast: return "Focus last column"
        case .moveLeft: return "Move column left"
        case .moveRight: return "Move column right"
        case .moveUp: return "Move window up in stack"
        case .moveDown: return "Move window down in stack"
        case .cycleWidth: return "Cycle width"
        case .cycleWidthBackward: return "Cycle width backward"
        case .narrower: return "Narrower"
        case .wider: return "Wider"
        case .toggleFullWidth: return "Toggle full width"
        case .center: return "Centre column"
        case .consumeIntoLeft: return "Stack into left column"
        case .consumeIntoRight: return "Stack into right column"
        case .expelLeft: return "Pop out of stack to the left"
        case .expel: return "Pop out of stack to the right"
        case .toggleFloat: return "Float / tile window"
        case .pinLeft: return "Pin column to left edge"
        case .pinRight: return "Pin column to right edge"
        case .toggleTabbed: return "Tabbed column on / off"
        case .cycleLayout: return "Next slide layout"
        case .mainLarger: return "Main window larger"
        case .mainSmaller: return "Main window smaller"
        case .makeMain: return "Make main window"
        case .regroup: return "Reset to smart pairs"
        case .overview: return "Overview of all windows"
        case .toggleNativeFullScreen: return "macOS full screen"
        case .windowSwitcher: return "Search windows"
        case .sendToNextDisplay: return "Send to next display"
        case .snapLeftHalf: return "Snap: left half"
        case .snapRightHalf: return "Snap: right half"
        case .snapTopHalf: return "Snap: top half"
        case .snapBottomHalf: return "Snap: bottom half"
        case .snapFirstThird: return "Snap: first third"
        case .snapCenterThird: return "Snap: centre third"
        case .snapLastThird: return "Snap: last third"
        case .snapFirstTwoThirds: return "Snap: first two thirds"
        case .snapLastTwoThirds: return "Snap: last two thirds"
        case .snapTopLeft: return "Snap: top-left quarter"
        case .snapTopRight: return "Snap: top-right quarter"
        case .snapBottomLeft: return "Snap: bottom-left quarter"
        case .snapBottomRight: return "Snap: bottom-right quarter"
        case .snapMaximize: return "Snap: maximise"
        case .snapCenter: return "Snap: centre"
        case .snapRestore: return "Snap: restore"
        case .setMark: return "Mark window (then a letter)"
        case .jumpToMark: return "Jump to mark (then a letter)"
        case .toggleScratchpad: return "Show / hide scratchpad"
        case .makeScratchpad: return "Make this window the scratchpad"
        case .nextProfile: return "Next profile"
        case .toggleFocusMode: return "Focus mode on / off"
        case .commandPalette: return "Command palette"
        case .takeSnapshot: return "Take a session snapshot"
        case .toggleSticky: return "Show window on every workspace"
        case .zoomTile: return "Zoom tile to fill the slide"
        case .lastWindow: return "Back to the last window"
        case .quickLaunch: return "Quick launch (then a letter)"
        case .pictureInPicture: return "Picture in picture"
        case .retile: return "Retile everything"
        case .undo: return "Undo last layout change"
        case .togglePause: return "Pause / resume"
        default:
            if let n = columnNumber { return "Focus column \(n)" }
            if let n = workspaceNumber { return "Switch to workspace \(n)" }
            if let n = moveToWorkspaceNumber { return "Move window to workspace \(n)" }
            return rawValue
        }
    }

    /// Where a "snap" action puts a floating window.
    public var snapPosition: SnapPosition? {
        switch self {
        case .snapLeftHalf: return .leftHalf
        case .snapRightHalf: return .rightHalf
        case .snapTopHalf: return .topHalf
        case .snapBottomHalf: return .bottomHalf
        case .snapFirstThird: return .firstThird
        case .snapCenterThird: return .centerThird
        case .snapLastThird: return .lastThird
        case .snapFirstTwoThirds: return .firstTwoThirds
        case .snapLastTwoThirds: return .lastTwoThirds
        case .snapTopLeft: return .topLeft
        case .snapTopRight: return .topRight
        case .snapBottomLeft: return .bottomLeft
        case .snapBottomRight: return .bottomRight
        case .snapMaximize: return .maximize
        case .snapCenter: return .center
        default: return nil
        }
    }

    /// 1...9 for the "focus column N" actions.
    public var columnNumber: Int? {
        let prefix = "focus-column-"
        guard rawValue.hasPrefix(prefix) else { return nil }
        return Int(rawValue.dropFirst(prefix.count))
    }

    /// 1...9 for the "switch to workspace N" actions.
    public var workspaceNumber: Int? {
        let prefix = "workspace-"
        guard rawValue.hasPrefix(prefix) else { return nil }
        return Int(rawValue.dropFirst(prefix.count))
    }

    /// 1...9 for the "move window to workspace N" actions.
    public var moveToWorkspaceNumber: Int? {
        let prefix = "move-to-workspace-"
        guard rawValue.hasPrefix(prefix) else { return nil }
        return Int(rawValue.dropFirst(prefix.count))
    }

    /// Parses `monorail://<action>` (or the older `macslider://<action>`, or a bare name).
    public init?(url: String) {
        var name = Substring(url)
        if let scheme = url.firstIndex(of: ":"), url[scheme...].hasPrefix("://") {
            name = url[url.index(scheme, offsetBy: 3)...]
        }
        while name.hasSuffix("/") { name.removeLast() }
        self.init(rawValue: name.lowercased())
    }
}
