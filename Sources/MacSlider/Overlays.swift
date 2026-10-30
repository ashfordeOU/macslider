#if os(macOS)
import AppKit
import MacSliderCore
import SwiftUI

/// Click-through panels drawn around and over other apps' windows:
/// the focus border, the inactive-window dimming and tab bars.
final class Overlays {
    struct Tab: Identifiable, Equatable {
        var id: WindowID
        var title: String
    }

    struct TabBarModel: Equatable {
        var frame: CGRect
        var tabs: [Tab]
        var active: Int
    }

    var onSelectWindow: (WindowID) -> Void = { _ in }

    private var border: NSPanel?
    private var dimPanels: [NSPanel] = []
    private var tabPanels: [NSPanel] = []

    /// Hides the overlays that track window positions (while windows move).
    func hideTransient() {
        border?.orderOut(nil)
        dimPanels.forEach { $0.orderOut(nil) }
    }

    func hideAll() {
        hideTransient()
        tabPanels.forEach { $0.orderOut(nil) }
    }

    func update(
        focused: (WindowID, CGRect)?,
        inactive: [(WindowID, CGRect)],
        tabBars: [TabBarModel],
        settings: AppSettings
    ) {
        updateBorder(focused: focused, settings: settings)
        updateDimming(inactive: settings.dimInactive ? inactive : [], amount: settings.dimAmount)
        updateTabBars(tabBars)
    }

    // MARK: Focus border

    private func updateBorder(focused: (WindowID, CGRect)?, settings: AppSettings) {
        guard settings.focusBorder, let (id, frame) = focused else {
            border?.orderOut(nil)
            return
        }
        let width = CGFloat(max(1, min(settings.focusBorderWidth, 12)))
        let panel = border ?? makePanel(clickThrough: true)
        border = panel
        let view: BorderView
        if let existing = panel.contentView as? BorderView {
            view = existing
        } else {
            view = BorderView()
            panel.contentView = view
        }
        view.color = NSColor(hex: settings.focusBorderColor) ?? .controlAccentColor
        view.lineWidth = width
        view.needsDisplay = true
        panel.setFrame(cocoaFrame(frame.insetBy(dx: -width, dy: -width)), display: true)
        panel.order(.above, relativeTo: Int(id))
    }

    // MARK: Dimming

    private func updateDimming(inactive: [(WindowID, CGRect)], amount: Double) {
        while dimPanels.count < inactive.count {
            let panel = makePanel(clickThrough: true)
            let view = NSView()
            view.wantsLayer = true
            panel.contentView = view
            dimPanels.append(panel)
        }
        for (index, panel) in dimPanels.enumerated() {
            guard index < inactive.count else {
                panel.orderOut(nil)
                continue
            }
            let (id, frame) = inactive[index]
            panel.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(amount)).cgColor
            panel.setFrame(cocoaFrame(frame), display: true)
            panel.order(.above, relativeTo: Int(id))
        }
    }

    // MARK: Tab bars

    private func updateTabBars(_ bars: [TabBarModel]) {
        while tabPanels.count < bars.count {
            tabPanels.append(makePanel(clickThrough: false))
        }
        for (index, panel) in tabPanels.enumerated() {
            guard index < bars.count else {
                panel.orderOut(nil)
                continue
            }
            let bar = bars[index]
            let view = TabBarView(model: bar) { [weak self] id in self?.onSelectWindow(id) }
            if let host = panel.contentView as? NSHostingView<TabBarView> {
                host.rootView = view
            } else {
                panel.contentView = NSHostingView(rootView: view)
            }
            panel.setFrame(cocoaFrame(bar.frame), display: true)
            panel.orderFrontRegardless()
        }
    }

    // MARK: Helpers

    private func makePanel(clickThrough: Bool) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = clickThrough
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenNone]
        panel.level = .normal
        return panel
    }

    /// Accessibility coordinates (top-left origin) to Cocoa (bottom-left origin).
    private func cocoaFrame(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

private final class BorderView: NSView {
    var color: NSColor = .controlAccentColor
    var lineWidth: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        let inset = lineWidth / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: 11, yRadius: 11)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }
}

private struct TabBarView: View {
    let model: Overlays.TabBarModel
    let select: (WindowID) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                Button {
                    select(tab.id)
                } label: {
                    Text(tab.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(size: 12, weight: index == model.active ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index == model.active ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08))
                        )
                        .foregroundStyle(index == model.active ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension NSColor {
    /// Parses "#RRGGBB" or "RRGGBB".
    convenience init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#4C8DFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif

#if os(macOS)
/// The cheat sheet shown at the bottom of the screen while slide mode is on.
final class SlideHUD {
    private var panel: NSPanel?

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: 640, height: 56)
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(
                NSRect(x: visible.midX - size.width / 2, y: visible.minY + 40, width: size.width, height: size.height),
                display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: SlideHUDView())
        host.frame.size = host.fittingSize
        panel.contentView = host
        return panel
    }
}

private struct SlideHUDView: View {
    var body: some View {
        HStack(spacing: 14) {
            Label("Slide", systemImage: "rectangle.split.3x1.fill")
                .font(.system(size: 13, weight: .semibold))
            ForEach(SlideMode.hints, id: \.keys) { hint in
                HStack(spacing: 5) {
                    Text(hint.keys)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
                    Text(hint.label).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}
#endif
