#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

/// Window hints (⌃⌥V): a letter on every window on screen; type one to go there.
final class WindowHints {
    private var panels: [NSPanel] = []
    private(set) var isShown = false

    static let letters = Array("asdfghjklqwertyuiopzxcvbnm").map(String.init)

    /// Shows the letters and returns them, mapped to their windows.
    func show(_ windows: [(id: WindowID, frame: CGRect, app: String)]) -> [String: WindowID] {
        hide()
        guard let primary = NSScreen.screens.first else { return [:] }
        var map: [String: WindowID] = [:]
        for (index, window) in windows.prefix(Self.letters.count).enumerated() {
            let letter = Self.letters[index]
            map[letter] = window.id
            let size = CGSize(width: 84, height: 84)
            let frame = NSRect(
                x: window.frame.midX - size.width / 2, y: primary.frame.height - window.frame.midY - size.height / 2,
                width: size.width, height: size.height)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .popUpMenu
            panel.ignoresMouseEvents = true
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: HintView(letter: letter, app: window.app))
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        isShown = !panels.isEmpty
        return map
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        isShown = false
    }
}

private struct HintView: View {
    let letter: String
    let app: String

    var body: some View {
        VStack(spacing: 2) {
            Text(letter.uppercased())
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(app).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }
        .frame(width: 80, height: 80)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.gradient))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.6), lineWidth: 2))
        .accessibilityLabel("\(letter) for \(app)")
    }
}

// MARK: - Zooming out on the strip

final class StripZoomModel: ObservableObject {
    @Published var map: Engine.MiniMap?
    @Published var thumbnails: [WindowID: NSImage] = [:]
    /// 0 = the screen as it is, 1 = the whole strip fitted to the screen.
    @Published var progress: Double = 0
}

/// Pinch out with ⌥ (or ⌃⌥⇧Z): the strip shrinks live under your fingers
/// until all of it fits on screen. Click a slide (or pinch back in) to go there.
final class StripZoom {
    var mapProvider: () -> Engine.MiniMap? = { nil }
    var focus: (WindowID) -> Void = { _ in }

    private let model = StripZoomModel()
    private var panel: NSPanel?
    private var monitor: Any?
    private(set) var isShown = false

    func toggle() {
        isShown ? close() : open(progress: 1)
    }

    /// Follows a pinch: negative totals zoom out.
    func pinch(_ total: Double, ended: Bool) {
        let progress = min(max(-total / 0.6, 0), 1)
        if !isShown {
            guard progress > 0.03 else { return }
            open(progress: progress)
        }
        model.progress = progress
        if ended {
            if progress > 0.35 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.progress = 1 }
            } else {
                close()
            }
        }
    }

    private func open(progress: Double) {
        guard let map = mapProvider(), !map.tiles.isEmpty else { return }
        model.map = map
        model.thumbnails = [:]
        if WindowThumbnails.isAllowed {
            WindowThumbnails.capture(map.tiles.flatMap { $0.windows.map(\.id) }) { [weak self] in self?.model.thumbnails = $0 }
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen { panel.setFrame(screen.frame, display: true) }
        withAnimation(.easeOut(duration: 0.2)) { model.progress = progress }
        panel.orderFrontRegardless()
        panel.makeKey()
        isShown = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == KeyCode.escape { self?.close() }
            return event
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        isShown = false
        model.progress = 0
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: StripZoomView(model: model) { [weak self] id in
            self?.close()
            self?.focus(id)
        } dismiss: { [weak self] in self?.close() })
        return panel
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct StripZoomView: View {
    @ObservedObject var model: StripZoomModel
    let choose: (WindowID) -> Void
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            if let map = model.map {
                let size = geometry.size
                // From the screen's own scale (1:1) to the whole strip fitted in 90% of the width.
                let fit = Double(size.width) * 0.9 / max(map.totalWidth, map.viewportWidth, 1)
                let full = Double(size.width) / max(map.viewportWidth, 1)
                let scale = full + (fit - full) * model.progress
                let height = Double(size.height) * 0.62 * (0.55 + 0.45 * (1 - model.progress))
                // Keep what is on screen in the middle as it shrinks.
                let centre = map.viewportX + map.viewportWidth / 2
                let originX = Double(size.width) / 2 - centre * scale
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.55 * model.progress)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismiss)
                    ForEach(map.tiles) { tile in
                        let x = originX + (map.isRightToLeft ? (map.totalWidth - tile.x - tile.width) : tile.x) * scale
                        let width = max(tile.width * scale - 12 * model.progress, 20)
                        SlideCard(tile: tile, thumbnails: model.thumbnails, choose: choose)
                            .frame(width: width, height: height)
                            .offset(x: x, y: (Double(size.height) - height) / 2)
                    }
                    if model.progress > 0.6 {
                        Text("Click a slide to go there · esc to close")
                            .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .offset(y: (Double(size.height) + height) / 2 + 20)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct SlideCard: View {
    let tile: Engine.MiniTile
    let thumbnails: [WindowID: NSImage]
    let choose: (WindowID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let frames = tile.arrangement.unitFrames(count: tile.windows.count, split: tile.split, rows: tile.customRows)
            ZStack(alignment: .topLeading) {
                ForEach(Array(tile.windows.enumerated()), id: \.element.id) { index, window in
                    let unit = frames.indices.contains(index) ? frames[index] : Rect(x: 0, y: 0, width: 1, height: 1)
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.18))
                        if let image = thumbnails[window.id] {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Text(window.appName).font(.headline).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(width: max(unit.width * geometry.size.width - 6, 4), height: max(unit.height * geometry.size.height - 6, 4))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tile.isFocused ? Color.accentColor : .white.opacity(0.2), lineWidth: tile.isFocused ? 3 : 1))
                    .offset(x: unit.minX * geometry.size.width + 3, y: unit.minY * geometry.size.height + 3)
                    .onTapGesture { choose(window.id) }
                    .accessibilityLabel("\(window.appName), \(window.title)")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}
#endif
