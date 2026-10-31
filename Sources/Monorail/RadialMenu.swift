#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

/// ⌃⌥E: a ring appears at the pointer. Move towards a side or corner and the
/// screen shows where the window will go; let go of ⌃⌥ (or click) to snap it
/// there. The middle fills the screen. Escape cancels. After a quick tap the
/// ring stays open until you click.
final class RadialMenu {
    /// Where a choice would put the focused window (Accessibility coordinates).
    var preview: (SnapPosition) -> CGRect? = { _ in nil }
    var apply: (SnapPosition) -> Void = { _ in }

    private let model = RadialModel()
    private var ring: NSPanel?
    private var outline: NSPanel?
    private var timer: Timer?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var center: CGPoint = .zero
    private var shownAt: CFTimeInterval = 0
    private(set) var isShown = false

    static let size: CGFloat = 220

    /// The eight directions, clockwise from the top, then the middle.
    static let sectors: [SnapPosition] = [
        .topHalf, .topRight, .rightHalf, .bottomRight, .bottomHalf, .bottomLeft, .leftHalf, .topLeft,
    ]

    func toggle() {
        isShown ? cancel() : show()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        shownAt = CACurrentMediaTime()
        center = NSEvent.mouseLocation
        let ring = self.ring ?? makePanel(size: CGSize(width: Self.size, height: Self.size), view: AnyView(RadialView(model: model)))
        self.ring = ring
        ring.setFrame(NSRect(x: center.x - Self.size / 2, y: center.y - Self.size / 2, width: Self.size, height: Self.size), display: true)
        ring.alphaValue = 0
        ring.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.1; ring.animator().alphaValue = 1 }
        model.selection = nil
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.track() }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == KeyCode.escape { self?.cancel() }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in self?.commit() }
    }

    /// Called as modifier keys change: letting go of ⌃ and ⌥ commits.
    func modifiersChanged(_ modifiers: Modifiers) {
        guard isShown, !modifiers.contains(.control) || !modifiers.contains(.option) else { return }
        // A quick tap leaves the ring open (click to choose); a hold commits on release.
        let held = CACurrentMediaTime() - shownAt > 0.45
        if held || (model.selection != nil && model.selection != .maximize) { commit() }
    }

    private func track() {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - center.x, dy = mouse.y - center.y
        let selection: SnapPosition
        if hypot(dx, dy) < 28 {
            selection = .maximize
        } else {
            // 0 = up, clockwise in eighths.
            let angle = atan2(dx, dy)
            let index = Int(((angle < 0 ? angle + 2 * .pi : angle) / (2 * .pi) * 8).rounded()) % 8
            selection = Self.sectors[index]
        }
        guard selection != model.selection else { return }
        model.selection = selection
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        showOutline(for: selection)
    }

    /// Outlines on screen where the window will go.
    private func showOutline(for position: SnapPosition) {
        guard let target = preview(position), let primary = NSScreen.screens.first else { return }
        let frame = NSRect(x: target.minX, y: primary.frame.height - target.maxY, width: target.width, height: target.height)
        let outline = self.outline ?? makePanel(size: frame.size, view: AnyView(OutlineView()))
        self.outline = outline
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            outline.animator().setFrame(frame, display: true)
        }
        if !outline.isVisible { outline.orderFrontRegardless() }
        ring?.orderFrontRegardless()
    }

    private func commit() {
        guard isShown else { return }
        let choice = model.selection
        close()
        if let choice { apply(choice) }
    }

    func cancel() { close() }

    private func close() {
        isShown = false
        timer?.invalidate()
        timer = nil
        for monitor in [keyMonitor, clickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        clickMonitor = nil
        ring?.orderOut(nil)
        outline?.orderOut(nil)
    }

    private func makePanel(size: CGSize, view: AnyView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}

final class RadialModel: ObservableObject {
    @Published var selection: SnapPosition?
}

private struct RadialView: View {
    @ObservedObject var model: RadialModel

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            ForEach(Array(RadialMenu.sectors.enumerated()), id: \.offset) { index, position in
                let on = model.selection == position
                Capsule()
                    .fill(on ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: on ? 34 : 26, height: 8)
                    .rotationEffect(.degrees(Double(index) * 45 - 90))
                    .offset(x: 78 * sin(Double(index) * .pi / 4), y: -78 * cos(Double(index) * .pi / 4))
                    .animation(.easeOut(duration: 0.1), value: on)
            }
            Circle()
                .fill(model.selection == .maximize ? Color.accentColor : Color.primary.opacity(0.12))
                .frame(width: 44, height: 44)
            Text(model.selection.map(Self.title) ?? "Move the pointer")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .offset(y: 40)
                .foregroundStyle(.secondary)
        }
        .padding(6)
    }

    static func title(_ position: SnapPosition) -> String {
        switch position {
        case .leftHalf: return "Left half"
        case .rightHalf: return "Right half"
        case .topHalf: return "Top half"
        case .bottomHalf: return "Bottom half"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        case .maximize: return "Fill the screen"
        default: return ""
        }
    }
}

private struct OutlineView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.accentColor.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3))
    }
}

/// A small label with a window's size while it is resized by hand.
final class ResizeHUD {
    private var panel: NSPanel?
    private let model = HUDModel()
    private var hideTimer: Timer?

    func show(_ frame: CGRect?) {
        guard let frame, let primary = NSScreen.screens.first else {
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                self?.panel?.orderOut(nil)
            }
            return
        }
        hideTimer?.invalidate()
        model.text = "\(Int(frame.width)) × \(Int(frame.height))"
        let size = CGSize(width: 130, height: 34)
        let panel = self.panel ?? {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .popUpMenu
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: HUDView(model: model))
            return panel
        }()
        self.panel = panel
        let cocoaY = primary.frame.height - frame.midY
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: cocoaY - size.height / 2, width: size.width, height: size.height),
                       display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
        // In case the end of the resize is never reported.
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in self?.panel?.orderOut(nil) }
    }
}

final class HUDModel: ObservableObject {
    @Published var text = ""
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        Text(model.text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(Color.black.opacity(0.7)))
    }
}
#endif
