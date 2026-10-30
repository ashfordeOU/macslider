#if os(macOS)
import AppKit
import MacSliderCore
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
        let names = commands.workspaceNames()
        if names.count > 1 {
            Menu("Move to Workspace") {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    Button(name) { commands.moveToWorkspace(window, index) }
                        .disabled(commands.currentWorkspace(window) == index)
                }
            }
        }
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
    static func ask(title: String, message: String, initial: String, placeholder: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Rename")
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

/// One colour per workspace, used by the overview and the slider bar.
enum WorkspaceColor {
    static let all: [Color] = [
        Color(red: 0.36, green: 0.56, blue: 1.0),
        Color(red: 0.69, green: 0.42, blue: 1.0),
        Color(red: 1.0, green: 0.38, blue: 0.62),
        Color(red: 1.0, green: 0.58, blue: 0.27),
        Color(red: 0.27, green: 0.82, blue: 0.55),
        Color(red: 0.2, green: 0.8, blue: 0.86),
        Color(red: 1.0, green: 0.8, blue: 0.25),
        Color(red: 1.0, green: 0.36, blue: 0.36),
        Color(red: 0.45, green: 0.45, blue: 0.95),
    ]

    static func color(_ index: Int) -> Color { all[((index % all.count) + all.count) % all.count] }
}
#endif
