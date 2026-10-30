#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

/// One thing the command palette can do.
struct PaletteCommand: Identifiable {
    var id: String
    var title: String
    var subtitle: String = ""
    var symbol: String = "command"
    /// Extra words it answers to ("pair", "park"…).
    var keywords: String = ""
    var run: () -> Void
}

final class PaletteModel: ObservableObject {
    @Published var query = "" {
        didSet { selection = 0 }
    }
    @Published var selection = 0
    @Published var commands: [PaletteCommand] = []

    /// Every typed word must appear somewhere in the command; earlier and
    /// title matches rank first.
    var filtered: [PaletteCommand] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return commands }
        return commands.compactMap { command -> (PaletteCommand, Int)? in
            let title = command.title.lowercased()
            let haystack = "\(title) \(command.subtitle.lowercased()) \(command.keywords.lowercased())"
            guard terms.allSatisfy({ haystack.contains($0) }) else { return nil }
            let score = terms.reduce(0) { total, term in
                total + (title.hasPrefix(term) ? 0 : title.contains(term) ? 1 : 3)
            }
            return (command, score)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }
}

/// ⌃⌥/ : type what you want ("pair safari notes", "park chat", "focus") and press return.
struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    let run: (PaletteCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Type a command: go to, move to, open pair, park, snapshot, focus…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .onSubmit(submit)
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.filtered.prefix(60).enumerated()), id: \.element.id) { index, command in
                            row(command, selected: index == model.selection)
                                .id(index)
                                .onTapGesture { run(command) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { proxy.scrollTo($0) }
            }
            if model.filtered.isEmpty {
                Text("No matching commands").foregroundStyle(.secondary).padding()
            }
        }
        .frame(width: 620, height: 420)
        .background(.regularMaterial)
    }

    private func row(_ command: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.symbol)
                .frame(width: 22)
                .foregroundStyle(selected ? Color.white : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title).lineLimit(1)
                if !command.subtitle.isEmpty {
                    Text(command.subtitle).font(.caption).lineLimit(1)
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func submit() {
        let list = model.filtered
        guard list.indices.contains(model.selection) else { return }
        run(list[model.selection])
    }
}

final class CommandPalette {
    private let model = PaletteModel()
    private var panel: SwitcherPanel?
    /// Builds the commands each time the palette opens, so they're current.
    var commands: () -> [PaletteCommand] = { [] }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        model.commands = commands()
        model.query = ""
        model.selection = 0
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = panel.frame.size
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.12))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.contentView = NSHostingView(rootView: PaletteView(model: model) { [weak self] command in
            self?.run(command)
        })
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        return panel
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let count = min(model.filtered.count, 60)
        switch event.keyCode {
        case KeyCode.escape:
            panel?.orderOut(nil)
            return true
        case KeyCode.down:
            if count > 0 { model.selection = min(model.selection + 1, count - 1) }
            return true
        case KeyCode.up:
            model.selection = max(model.selection - 1, 0)
            return true
        default:
            return false
        }
    }

    private func run(_ command: PaletteCommand) {
        panel?.orderOut(nil)
        // Let focus return to the app underneath first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { command.run() }
    }
}
#endif
