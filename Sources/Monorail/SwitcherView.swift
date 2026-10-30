#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

final class SwitcherModel: ObservableObject {
    @Published var query = "" {
        didSet { selection = 0 }
    }
    @Published var selection = 0
    @Published var windows: [Engine.WindowSummary] = []

    var filtered: [Engine.WindowSummary] {
        let terms = query.lowercased().split(separator: " ")
        guard !terms.isEmpty else { return windows }
        return windows.filter { window in
            let haystack = "\(window.appName) \(window.title)".lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}

/// "Search windows": type to filter, ↑↓ to choose, Return to jump.
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let choose: (WindowID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search windows", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .onSubmit(submit)
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, window in
                            row(window, selected: index == model.selection)
                                .id(index)
                                .onTapGesture { choose(window.id) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { proxy.scrollTo($0) }
            }
            if model.filtered.isEmpty {
                Text("No matching windows").foregroundStyle(.secondary).padding()
            }
        }
        .frame(width: 560, height: 380)
        .background(.regularMaterial)
    }

    private func row(_ window: Engine.WindowSummary, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let icon = window.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(window.title.isEmpty ? window.appName : window.title).lineLimit(1)
                Text(window.isTiled ? window.appName : "\(window.appName) · floating")
                    .font(.caption).foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
    }

    private func submit() {
        let list = model.filtered
        guard list.indices.contains(model.selection) else { return }
        choose(list[model.selection].id)
    }
}

/// A floating search panel that can take keyboard focus.
final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onKey: (NSEvent) -> Bool = { _ in false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey(event) { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

final class SwitcherController {
    private let model = SwitcherModel()
    private var panel: SwitcherPanel?
    var windows: () -> [Engine.WindowSummary] = { [] }
    var choose: (WindowID) -> Void = { _ in }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        model.windows = windows()
        model.query = ""
        model.selection = model.windows.firstIndex { !$0.isFocused } ?? 0
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.contentView = NSHostingView(
            rootView: SwitcherView(model: model) { [weak self] id in self?.select(id) })
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        return panel
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let count = model.filtered.count
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

    private func select(_ id: WindowID) {
        panel?.orderOut(nil)
        choose(id)
    }
}
#endif
