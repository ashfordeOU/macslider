#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

/// The small popup that appears next to a window after you resize it in a
/// slide: keep it as it is, give it a slide of its own, move the other
/// windows out, or undo. It goes away by itself if you ignore it.
final class ResizeAssist {
    struct Actions {
        var ownSlide: (WindowID) -> Void
        var othersOut: (WindowID) -> Void
        var undo: () -> Void
    }

    var actions = Actions(ownSlide: { _ in }, othersOut: { _ in }, undo: {})
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private let model = Model()

    final class Model: ObservableObject {
        @Published var window: WindowID = 0
        @Published var appName = ""
        @Published var hasOthers = true
        @Published var isHovered = false
    }

    /// Shows the popup by the top edge of `frame` (Accessibility coordinates).
    func show(for window: WindowID, frame: CGRect, appName: String, hasOthers: Bool) {
        model.window = window
        model.appName = appName
        model.hasOthers = hasOthers
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: 520, height: 46)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let top = primaryHeight - frame.minY
        var origin = NSPoint(x: frame.midX - size.width / 2, y: top - size.height - 44)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: frame.midX, y: top - 1)) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        scheduleDismiss()
    }

    func dismiss() {
        dismissTimer?.invalidate()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.model.isHovered { self.scheduleDismiss() } else { self.dismiss() }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 46),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let view = AssistView(
            model: model,
            ownSlide: { [weak self] in self.map { $0.actions.ownSlide($0.model.window); $0.dismiss() } },
            othersOut: { [weak self] in self.map { $0.actions.othersOut($0.model.window); $0.dismiss() } },
            undo: { [weak self] in self.map { $0.actions.undo(); $0.dismiss() } },
            keep: { [weak self] in self?.dismiss() })
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        panel.contentView = host
        return panel
    }

    private struct AssistView: View {
        @ObservedObject var model: Model
        let ownSlide: () -> Void
        let othersOut: () -> Void
        let undo: () -> Void
        let keep: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.secondary)
                Text("Resized \(model.appName)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Divider().frame(height: 18)
                Button("Keep", action: keep)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                if model.hasOthers {
                    Button(action: ownSlide) { Label("Own slide", systemImage: "rectangle.portrait.and.arrow.right") }
                        .help("Move this window to a slide of its own")
                    Button(action: othersOut) { Label("Move others out", systemImage: "rectangle.stack.badge.minus") }
                        .help("Keep this window here and move the rest of the slide to a new slide")
                }
                Button(action: undo) { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo the resize")
                Button(action: keep) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .fixedSize()
            .onHover { model.isHovered = $0 }
        }
    }
}
#endif
