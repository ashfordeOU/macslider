#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

/// What can be done to a window from a preview or the overview.
struct WindowCommands {
    var focus: (WindowID) -> Void = { _ in }
    var close: (WindowID) -> Void = { _ in }
    var minimize: (WindowID) -> Void = { _ in }
    var fullScreen: (WindowID) -> Void = { _ in }
    var ownSlide: (WindowID) -> Void = { _ in }
    var rename: (WindowID) -> Void = { _ in }
    var moveToWorkspace: (WindowID, Int) -> Void = { _, _ in }
    var workspaceNames: () -> [String] = { [] }
    var currentWorkspace: (WindowID) -> Int? = { _ in nil }
    /// nil arrangement means tabs.
    var setLayout: (WindowID, Arrangement?) -> Void = { _, _ in }
    /// The slide's layout (inner nil = tabs); outer nil if the window isn't tiled.
    var currentLayout: (WindowID) -> Arrangement?? = { _ in nil }
    /// The user's own layouts, and setting one on a slide.
    var customLayouts: () -> [CustomLayout] = { [] }
    var setCustomLayout: (WindowID, [Int]) -> Void = { _, _ in }
    var currentRows: (WindowID) -> [Int]? = { _ in nil }
    /// Saves the slide's apps as an app pair.
    var saveAppPair: (WindowID) -> Void = { _ in }
    /// Windows that follow you to every workspace.
    var isSticky: (WindowID) -> Bool = { _ in false }
    var toggleSticky: (WindowID) -> Void = { _ in }
    /// A live picture of the window in a screen corner.
    var pictureInPicture: (WindowID) -> Void = { _ in }
    /// Name and lock the slide holding a window.
    var nameSlide: (WindowID) -> Void = { _ in }
    var isSlideLocked: (WindowID) -> Bool = { _ in false }
    var toggleLock: (WindowID) -> Void = { _ in }
    /// Stop managing the window's app altogether.
    var neverManage: (WindowID) -> Void = { _ in }
    /// Float the window at an exact size, centred.
    var setSize: (WindowID, CGSize) -> Void = { _, _ in }
}

/// Sizes for recordings and screenshots.
let standardSizes: [(String, CGSize)] = [
    ("1280 × 720 (720p)", CGSize(width: 1280, height: 720)),
    ("1440 × 900", CGSize(width: 1440, height: 900)),
    ("1920 × 1080 (1080p)", CGSize(width: 1920, height: 1080)),
    ("2560 × 1440", CGSize(width: 2560, height: 1440)),
    ("1080 × 1080 (square)", CGSize(width: 1080, height: 1080)),
]

/// "Slide Layout ▸" for the slide holding a window.
struct SlideLayoutMenu: View {
    let window: WindowID
    let commands: WindowCommands

    var body: some View {
        let current = commands.currentLayout(window)
        Menu("Slide Layout") {
            ForEach(Arrangement.standard, id: \.self) { arrangement in
                Button {
                    commands.setLayout(window, arrangement)
                } label: {
                    if current == .some(.some(arrangement)) {
                        Label(arrangement.title, systemImage: "checkmark")
                    } else {
                        Text(arrangement.title)
                    }
                }
            }
            Button {
                commands.setLayout(window, nil)
            } label: {
                if current == .some(.none) { Label("Tabs", systemImage: "checkmark") } else { Text("Tabs") }
            }
            let custom = commands.customLayouts()
            if !custom.isEmpty {
                Divider()
                let rows = current == .some(.some(.custom)) ? commands.currentRows(window) : nil
                ForEach(custom) { layout in
                    Button {
                        commands.setCustomLayout(window, layout.rows)
                    } label: {
                        if rows == layout.rows { Label(layout.name, systemImage: "checkmark") } else { Text(layout.name) }
                    }
                }
            }
        }
    }
}

/// Close, minimise and full-screen buttons, like a window's title bar.
struct TrafficLights: View {
    let window: WindowID
    let commands: WindowCommands
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            light(Color(red: 1, green: 0.37, blue: 0.34), symbol: "xmark", help: "Close") { commands.close(window) }
            light(Color(red: 1, green: 0.74, blue: 0.18), symbol: "minus", help: "Minimise") { commands.minimize(window) }
            light(Color(red: 0.16, green: 0.78, blue: 0.25), symbol: "arrow.up.left.and.arrow.down.right",
                  help: "Full screen") { commands.fullScreen(window) }
        }
        .padding(5)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .onHover { hovered = $0 }
    }

    private func light(_ color: Color, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
                if hovered {
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
            .frame(width: 12, height: 12)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The right-click menu for a window tile.
struct WindowContextMenu: View {
    let window: WindowID
    let commands: WindowCommands

    var body: some View {
        Button("Rename…") { commands.rename(window) }
        Divider()
        Button("Focus") { commands.focus(window) }
        Button("Give It Its Own Slide") { commands.ownSlide(window) }
        if commands.currentLayout(window) != nil {
            SlideLayoutMenu(window: window, commands: commands)
            Button("Save Slide as App Pair…") { commands.saveAppPair(window) }
            Button("Name Slide…") { commands.nameSlide(window) }
            Button(commands.isSlideLocked(window) ? "Unlock Slide" : "Lock Slide") { commands.toggleLock(window) }
        }
        let names = commands.workspaceNames()
        if names.count > 1 {
            Menu("Move to Workspace") {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    Button(name) { commands.moveToWorkspace(window, index) }
                        .disabled(commands.currentWorkspace(window) == index)
                }
            }
        }
        Button(commands.isSticky(window) ? "Keep in This Workspace Only" : "Show on Every Workspace") {
            commands.toggleSticky(window)
        }
        Button("Picture in Picture") { commands.pictureInPicture(window) }
        Menu("Size for Recording") {
            ForEach(Array(standardSizes.enumerated()), id: \.offset) { _, entry in
                Button(entry.0) { commands.setSize(window, entry.1) }
            }
        }
        Button("Never Manage This App") { commands.neverManage(window) }
        Divider()
        Button("Full Screen") { commands.fullScreen(window) }
        Button("Minimise") { commands.minimize(window) }
        Button("Close") { commands.close(window) }
    }
}

extension View {
    /// Adds the traffic lights (top-left) and the right-click menu to a window tile.
    func windowControls(_ window: WindowID, _ commands: WindowCommands, showLights: Bool = true) -> some View {
        overlay(alignment: .topLeading) {
            if showLights { TrafficLights(window: window, commands: commands).padding(6) }
        }
        .contextMenu { WindowContextMenu(window: window, commands: commands) }
    }
}

/// A small modal text prompt (renaming windows and workspaces).
enum TextPrompt {
    static func ask(
        title: String, message: String, initial: String, placeholder: String = "", button: String = "Rename"
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}

/// One colour per workspace, used by the overview and the slider bar, from
/// the chosen theme.
enum WorkspaceColor {
    /// Set from Settings → Appearance.
    static var theme: Theme = .vivid

    static func palette(_ theme: Theme) -> [Color] {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch theme {
        case .vivid:
            return [rgb(0.36, 0.56, 1.0), rgb(0.69, 0.42, 1.0), rgb(1.0, 0.38, 0.62), rgb(1.0, 0.58, 0.27),
                    rgb(0.27, 0.82, 0.55), rgb(0.2, 0.8, 0.86), rgb(1.0, 0.8, 0.25), rgb(1.0, 0.36, 0.36),
                    rgb(0.45, 0.45, 0.95)]
        case .ocean:
            return [rgb(0.2, 0.62, 1.0), rgb(0.16, 0.82, 0.86), rgb(0.35, 0.45, 0.98), rgb(0.3, 0.9, 0.72),
                    rgb(0.55, 0.75, 1.0), rgb(0.12, 0.55, 0.75), rgb(0.6, 0.9, 0.95), rgb(0.4, 0.35, 0.85),
                    rgb(0.25, 0.7, 0.6)]
        case .sunset:
            return [rgb(1.0, 0.55, 0.3), rgb(1.0, 0.36, 0.5), rgb(0.85, 0.35, 0.85), rgb(1.0, 0.78, 0.3),
                    rgb(0.95, 0.45, 0.35), rgb(0.6, 0.35, 0.9), rgb(1.0, 0.65, 0.55), rgb(0.9, 0.25, 0.4),
                    rgb(1.0, 0.85, 0.55)]
        case .forest:
            return [rgb(0.3, 0.75, 0.45), rgb(0.6, 0.8, 0.3), rgb(0.85, 0.7, 0.35), rgb(0.25, 0.6, 0.55),
                    rgb(0.7, 0.55, 0.35), rgb(0.45, 0.85, 0.6), rgb(0.9, 0.8, 0.45), rgb(0.55, 0.65, 0.4),
                    rgb(0.35, 0.5, 0.35)]
        case .mono:
            return [0.92, 0.78, 0.64, 0.86, 0.7, 0.56, 0.96, 0.6, 0.74].map { Color(white: $0) }
        }
    }

    /// The overview's backdrop: a gradient and three soft glows.
    static func backdrop(_ theme: Theme) -> (gradient: [Color], glows: [Color]) {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch theme {
        case .vivid:
            return ([rgb(0.13, 0.09, 0.36), rgb(0.36, 0.13, 0.5), rgb(0.05, 0.3, 0.46)],
                    [rgb(1, 0.38, 0.62), rgb(0.2, 0.8, 0.86), rgb(1, 0.58, 0.27)])
        case .ocean:
            return ([rgb(0.03, 0.12, 0.3), rgb(0.04, 0.25, 0.42), rgb(0.02, 0.35, 0.4)],
                    [rgb(0.2, 0.62, 1), rgb(0.16, 0.82, 0.86), rgb(0.35, 0.45, 0.98)])
        case .sunset:
            return ([rgb(0.3, 0.08, 0.2), rgb(0.45, 0.14, 0.24), rgb(0.35, 0.12, 0.4)],
                    [rgb(1, 0.55, 0.3), rgb(0.85, 0.35, 0.85), rgb(1, 0.78, 0.3)])
        case .forest:
            return ([rgb(0.05, 0.18, 0.12), rgb(0.1, 0.25, 0.15), rgb(0.12, 0.2, 0.1)],
                    [rgb(0.3, 0.75, 0.45), rgb(0.85, 0.7, 0.35), rgb(0.45, 0.85, 0.6)])
        case .mono:
            return ([Color(white: 0.1), Color(white: 0.16), Color(white: 0.12)],
                    [Color(white: 0.5), Color(white: 0.35), Color(white: 0.6)])
        }
    }

    static var all: [Color] { palette(theme) }

    static func color(_ index: Int) -> Color {
        let colors = all
        return colors[((index % colors.count) + colors.count) % colors.count]
    }
}
#endif
