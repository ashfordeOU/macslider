/// Everything MacSlider can do from a shortcut or a `macslider://` URL.
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
    case toggleGrid = "toggle-grid"
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
    case retile
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
        case .toggleGrid: return "Grid of tiles on / off"
        case .regroup: return "Group windows by app"
        case .overview: return "Overview of all windows"
        case .toggleNativeFullScreen: return "macOS full screen"
        case .windowSwitcher: return "Search windows"
        case .sendToNextDisplay: return "Send to next display"
        case .retile: return "Retile everything"
        case .togglePause: return "Pause / resume"
        default:
            if let n = columnNumber { return "Focus column \(n)" }
            if let n = workspaceNumber { return "Switch to workspace \(n)" }
            if let n = moveToWorkspaceNumber { return "Move window to workspace \(n)" }
            return rawValue
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

    /// Parses `macslider://<action>` (or a bare action name).
    public init?(url: String) {
        var name = Substring(url)
        if let scheme = url.firstIndex(of: ":"), url[scheme...].hasPrefix("://") {
            name = url[url.index(scheme, offsetBy: 3)...]
        }
        while name.hasSuffix("/") { name.removeLast() }
        self.init(rawValue: name.lowercased())
    }
}
