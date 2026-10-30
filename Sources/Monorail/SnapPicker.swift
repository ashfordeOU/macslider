#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

/// Drag a window towards the top of the screen and a strip of layouts drops
/// down; let go over a zone to snap the window there.
final class SnapPicker {
    /// Snaps the dragged window to a zone.
    var snap: (WindowID, SnapPosition) -> Void = { _, _ in }
    var isEnabled = true

    private let model = SnapPickerModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private var dragging: WindowID?

    /// The layouts offered, each a set of zones.
    static let groups: [[SnapPosition]] = [
        [.leftHalf, .rightHalf],
        [.firstThird, .centerThird, .lastThird],
        [.firstTwoThirds, .lastThird],
        [.firstThird, .lastTwoThirds],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.maximize],
    ]
    static let groupSize = CGSize(width: 76, height: 48)
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 12
    static var panelSize: CGSize {
        let count = CGFloat(groups.count)
        return CGSize(
            width: padding * 2 + count * groupSize.width + (count - 1) * spacing,
            height: padding * 2 + groupSize.height)
    }

    /// Each zone's rectangle in the panel (top-left origin).
    static let zones: [(position: SnapPosition, group: Int, rect: CGRect)] = {
        var result: [(position: SnapPosition, group: Int, rect: CGRect)] = []
        for (g, group) in groups.enumerated() {
            let box = CGRect(
                x: padding + CGFloat(g) * (groupSize.width + spacing), y: padding,
                width: groupSize.width, height: groupSize.height)
            for position in group {
                let unit = position.unit
                let rect = CGRect(
                    x: box.minX + CGFloat(unit.minX) * box.width, y: box.minY + CGFloat(unit.minY) * box.height,
                    width: CGFloat(unit.width) * box.width, height: CGFloat(unit.height) * box.height)
                result.append((position: position, group: g, rect: rect.insetBy(dx: 1.5, dy: 1.5)))
            }
        }
        return result
    }()

    /// Called when the user starts dragging a window.
    func windowDragStarted(_ id: WindowID) {
        guard isEnabled, dragging == nil, NSEvent.pressedMouseButtons != 0 else { return }
        dragging = id
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.track() }
    }

    private func track() {
        guard let id = dragging else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
        let visible = screen.visibleFrame
        let size = Self.panelSize
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 6)

        if NSEvent.pressedMouseButtons == 0 {
            // Dropped: snap if over a zone.
            let zone = model.hovered.map { Self.zones[$0].position }
            finish()
            if let zone { snap(id, zone) }
            return
        }

        let isShown = panel?.isVisible == true
        let near = mouse.y >= visible.maxY - 60 && abs(mouse.x - visible.midX) <= size.width / 2 + 80
        let stillNear = mouse.y >= visible.maxY - size.height - 70
        if !isShown && near {
            show(at: origin, size: size)
        } else if isShown && !stillNear {
            hide()
        }
        guard panel?.isVisible == true, let frame = panel?.frame else { return }
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let hovered = Self.zones.firstIndex { $0.rect.contains(local) }
        if model.hovered != hovered {
            model.hovered = hovered
            if hovered != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
    }

    private func show(at origin: CGPoint, size: CGSize) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        model.hovered = nil
        panel?.orderOut(nil)
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        dragging = nil
        hide()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: SnapPickerView(model: model))
        return panel
    }
}

final class SnapPickerModel: ObservableObject {
    /// Index into `SnapPicker.zones`.
    @Published var hovered: Int?
}

struct SnapPickerView: View {
    @ObservedObject var model: SnapPickerModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12))
            ForEach(Array(SnapPicker.groups.indices), id: \.self) { g in
                let box = CGRect(
                    x: SnapPicker.padding + CGFloat(g) * (SnapPicker.groupSize.width + SnapPicker.spacing),
                    y: SnapPicker.padding, width: SnapPicker.groupSize.width, height: SnapPicker.groupSize.height)
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
            }
            ForEach(Array(SnapPicker.zones.enumerated()), id: \.offset) { index, zone in
                let on = model.hovered == index
                RoundedRectangle(cornerRadius: 5)
                    .fill(on ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: zone.rect.width, height: zone.rect.height)
                    .offset(x: zone.rect.minX, y: zone.rect.minY)
                    .animation(.easeOut(duration: 0.1), value: on)
            }
        }
        .frame(width: SnapPicker.panelSize.width, height: SnapPicker.panelSize.height)
    }
}
#endif
