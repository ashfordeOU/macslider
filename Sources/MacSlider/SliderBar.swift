#if os(macOS)
import AppKit
import Combine
import MacSliderCore
import SwiftUI

/// The slider bar: a small glass mini-map of the strip on each display. Each
/// slide is a tile with its apps' icons; the highlighted frame is what's on
/// screen. Drag anywhere on it to slide every window along; click a tile to
/// jump there.
final class SliderBarController {
    struct Actions {
        var slide: (_ stripX: Double, _ displayUUID: String) -> Void
        var endSlide: () -> Void
        var focus: (WindowID) -> Void
        var switchWorkspace: (Int) -> Void
        var showOverview: () -> Void
        var renameWorkspace: (Int) -> Void = { _ in }
        var commands = WindowCommands()
    }

    var mode: SliderBarMode = .whileMoving
    var edge: SliderBarEdge = .bottom
    var mapsProvider: () -> [Engine.MiniMap] = { [] }
    var actions = Actions(slide: { _, _ in }, endSlide: {}, focus: { _ in }, switchWorkspace: { _ in }, showOverview: {})

    private var bars: [String: (panel: NSPanel, model: SliderBarModel)] = [:]
    private var hideTimer: Timer?
    private let preview = SlidePreview()
    private let tip = NameTip()
    private var subscriptions: [AnyCancellable] = []
    private static let height: CGFloat = 52
    private static let margin: CGFloat = 6

    /// Refreshes the bars. Called whenever the strips change.
    func update() {
        guard mode != .off else {
            hideAll(animated: false)
            return
        }
        let maps = mapsProvider()
        preview.sync(with: maps)
        let current = Set(maps.map(\.displayUUID))
        for (uuid, bar) in bars where !current.contains(uuid) {
            bar.panel.orderOut(nil)
            bars[uuid] = nil
        }

        var changed = false
        for map in maps {
            let bar = bars[map.displayUUID] ?? makeBar(for: map.displayUUID)
            bars[map.displayUUID] = bar
            if bar.model.map != map {
                changed = changed || bar.model.map?.viewportX != map.viewportX
                    || bar.model.map?.tiles != map.tiles || bar.model.map?.workspace != map.workspace
                bar.model.map = map
            }
            position(bar.panel, for: map)
            let empty = map.tiles.isEmpty
            if mode == .always {
                show(bar.panel)
            } else if empty {
                bar.panel.orderOut(nil)
            }
        }
        if mode == .whileMoving && changed {
            for bar in bars.values where !(bar.model.map?.tiles.isEmpty ?? true) { show(bar.panel) }
            scheduleHide()
        }
    }

    /// True if `point` (Cocoa coordinates) is over a visible slider bar, so
    /// scrolling there can slide the strip.
    func contains(_ point: CGPoint) -> Bool {
        bars.values.contains { $0.panel.isVisible && $0.panel.alphaValue > 0.5 && $0.panel.frame.contains(point) }
    }

    func hideAll(animated: Bool) {
        hideTimer?.invalidate()
        preview.hide()
        for bar in bars.values {
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    bar.panel.animator().alphaValue = 0
                }, completionHandler: { bar.panel.orderOut(nil) })
            } else {
                bar.panel.orderOut(nil)
            }
        }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            guard let self, self.mode == .whileMoving else { return }
            // Stay while the pointer is on a bar or its preview, or a drag is in progress.
            if self.preview.isHovered || self.bars.values.contains(where: { $0.model.isHovering || $0.model.isDragging }) {
                self.scheduleHide()
            } else {
                self.hideAll(animated: true)
            }
        }
    }

    private func show(_ panel: NSPanel) {
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func position(_ panel: NSPanel, for map: Engine.MiniMap) {
        let screen = map.screenFrame
        let width = min(max(screen.width * 0.5, 320), 820)
        let y = edge == .bottom
            ? screen.minY + Self.margin
            : screen.maxY - Self.height - Self.margin
        let frame = NSRect(x: screen.midX - width / 2, y: y, width: width, height: Self.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func makeBar(for uuid: String) -> (panel: NSPanel, model: SliderBarModel) {
        let model = SliderBarModel()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = SliderBarView(model: model, actions: actions) { [weak self] in self?.scheduleHide() }
        model.$hoveredTile
            .removeDuplicates { $0?.id == $1?.id && $0?.windows == $1?.windows }
            .sink { [weak self, weak panel] tile in
                guard let self, let panel else { return }
                self.preview.focus = self.actions.focus
                self.preview.commands = self.actions.commands
                self.preview.hover(tile, over: panel, edge: self.edge, number: tile.flatMap { tile in
                    model.map?.tiles.firstIndex { $0.id == tile.id }.map { $0 + 1 }
                })
            }
            .store(in: &subscriptions)
        model.$hoveredWorkspace
            .removeDuplicates()
            .sink { [weak self, weak panel] index in
                guard let self, let panel else { return }
                guard let index, let names = model.map?.workspaceNames, names.indices.contains(index) else {
                    self.tip.hide()
                    return
                }
                self.tip.show(names[index], color: WorkspaceColor.color(index), over: panel, edge: self.edge)
            }
            .store(in: &subscriptions)
        panel.contentView = NSHostingView(rootView: view)
        return (panel, model)
    }
}

final class SliderBarModel: ObservableObject {
    @Published var map: Engine.MiniMap?
    /// The tile under the pointer, for the live preview.
    @Published var hoveredTile: Engine.MiniTile?
    /// The workspace dot under the pointer, to show its name.
    @Published var hoveredWorkspace: Int?
    @Published var isHovering = false
    @Published var isDragging = false
}

private enum AppIcons {
    private static var cache: [pid_t: NSImage] = [:]

    static func icon(for pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        cache[pid] = icon
        return icon
    }
}

private struct SliderBarView: View {
    @ObservedObject var model: SliderBarModel
    let actions: SliderBarController.Actions
    let onInteraction: () -> Void

    @State private var dragScale: Double?
    @State private var dragOrigin: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            if let map = model.map, map.workspaceCount > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<map.workspaceCount, id: \.self) { index in
                        let name = map.workspaceNames.indices.contains(index)
                            ? map.workspaceNames[index] : "Workspace \(index + 1)"
                        Circle()
                            .fill(index == map.workspace ? WorkspaceColor.color(index) : Color.primary.opacity(0.25))
                            .frame(width: 8, height: 8)
                            .scaleEffect(model.hoveredWorkspace == index ? 1.35 : 1)
                            .animation(.easeOut(duration: 0.12), value: model.hoveredWorkspace)
                            .contentShape(Rectangle().inset(by: -4))
                            .onTapGesture { actions.switchWorkspace(index) }
                            .onHover { hovering in
                                if hovering {
                                    model.hoveredWorkspace = index
                                } else if model.hoveredWorkspace == index {
                                    model.hoveredWorkspace = nil
                                }
                            }
                            .contextMenu {
                                Button("Rename “\(name)”…") { actions.renameWorkspace(index) }
                                Button("Switch to \(name)") { actions.switchWorkspace(index) }
                            }
                    }
                }
            }
            GeometryReader { geometry in
                track(size: geometry.size)
            }
            Button(action: actions.showOverview) {
                Image(systemName: "square.grid.3x2")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Overview")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .onHover { hovering in
            model.isHovering = hovering
            if !hovering { onInteraction() }
        }
    }

    /// Strip-space range the track shows: the whole strip plus the viewport,
    /// even when the viewport hangs past either end.
    /// Track position of a strip x coordinate, mirrored for right-to-left strips.
    private func trackX(_ x: Double, width: Double, lower: Double, span: Double, scale: Double, map: Engine.MiniMap) -> Double {
        let left = (x - lower) * scale
        return map.isRightToLeft ? span * scale - left - width * scale : left
    }

    private func bounds(_ map: Engine.MiniMap) -> (min: Double, span: Double) {
        let lower = min(0, map.viewportX)
        let upper = max(map.totalWidth, map.viewportX + map.viewportWidth)
        return (lower, max(upper - lower, 1))
    }

    @ViewBuilder
    private func track(size: CGSize) -> some View {
        if let map = model.map {
            let (lower, span) = bounds(map)
            let scale = Double(size.width) / span
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.05))
                ForEach(map.tiles) { tile in
                    TileView(tile: tile, height: size.height - 8)
                        .frame(width: max(tile.width * scale - 3, 6), height: size.height - 8)
                        .offset(x: trackX(tile.x, width: tile.width, lower: lower, span: span, scale: scale, map: map) + 1.5, y: 4)
                        .onTapGesture {
                            if let window = tile.windows.first { actions.focus(window.id) }
                        }
                        .onHover { hovering in
                            if hovering {
                                model.hoveredTile = tile
                            } else if model.hoveredTile?.id == tile.id {
                                model.hoveredTile = nil
                            }
                        }
                }
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2))
                    .frame(width: max(map.viewportWidth * scale, 10), height: size.height)
                    .offset(x: trackX(map.viewportX, width: map.viewportWidth, lower: lower, span: span, scale: scale, map: map))
                    .allowsHitTesting(false)
                if map.tiles.isEmpty {
                    Text("No windows in this workspace")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: size.width, height: size.height)
                }
            }
            .animation(model.isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: map)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        // Freeze the mapping for the whole drag so the bar doesn't rescale under the pointer.
                        if dragScale == nil {
                            dragScale = scale
                            dragOrigin = lower
                            model.isDragging = true
                        }
                        let scaleNow = dragScale ?? scale
                        var trackPosition = Double(value.location.x)
                        if map.isRightToLeft { trackPosition = span * scaleNow - trackPosition }
                        let stripX = trackPosition / scaleNow + dragOrigin - map.viewportWidth / 2
                        actions.slide(stripX, map.displayUUID)
                    }
                    .onEnded { _ in
                        dragScale = nil
                        model.isDragging = false
                        actions.endSlide()
                        onInteraction()
                    }
            )
        }
    }
}

private struct TileView: View {
    let tile: Engine.MiniTile
    let height: CGFloat

    private var icons: [pid_t] {
        var seen: [pid_t] = []
        for window in tile.windows where !seen.contains(window.pid) { seen.append(window.pid) }
        return seen
    }

    var body: some View {
        let iconSize = min(max(height - 14, 10), 22)
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(tile.isFocused ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.10))
            if tile.windows.count > 1 {
                // Hint at the slide's layout with thin tile outlines.
                TileOutlines(frames: tile.arrangement.unitFrames(count: tile.windows.count, split: tile.split))
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    .padding(3)
            }
            HStack(spacing: 2) {
                ForEach(icons.prefix(4), id: \.self) { pid in
                    if let icon = AppIcons.icon(for: pid) {
                        Image(nsImage: icon).resizable().frame(width: iconSize, height: iconSize)
                    }
                }
                if tile.windows.count > 1 {
                    Text("\(tile.windows.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Outlines of a slide's tiles, from unit rectangles.
private struct TileOutlines: Shape {
    let frames: [Rect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for unit in frames {
            let x = rect.minX + CGFloat(unit.minX) * rect.width + 1
            let y = rect.minY + CGFloat(unit.minY) * rect.height + 1
            let width = max(CGFloat(unit.width) * rect.width - 2, 1)
            let height = max(CGFloat(unit.height) * rect.height - 2, 1)
            path.addRoundedRect(
                in: CGRect(x: x, y: y, width: width, height: height), cornerSize: CGSize(width: 2, height: 2))
        }
        return path
    }
}
// MARK: - Live preview

/// The popup that appears above a slider-bar tile: that slide's windows,
/// live, laid out as they are on screen. Click one to jump to it.
final class SlidePreview {
    var focus: (WindowID) -> Void = { _ in }
    var commands = WindowCommands()
    private(set) var isHovered = false

    private let model = PreviewModel()
    private var panel: NSPanel?
    private var showTimer: Timer?
    private var hideTimer: Timer?
    private var refreshTimer: Timer?
    private static let width: CGFloat = 440

    func hover(_ tile: Engine.MiniTile?, over bar: NSPanel, edge: SliderBarEdge, number: Int?) {
        showTimer?.invalidate()
        guard let tile, !tile.windows.isEmpty else {
            scheduleHide()
            return
        }
        hideTimer?.invalidate()
        let present = { [weak self] in
            guard let self else { return }
            self.model.tile = tile
            self.model.number = number ?? 0
            self.show(over: bar, edge: edge)
        }
        // Appear after a short pause; once open, follow the pointer instantly.
        if panel?.isVisible == true {
            present()
        } else {
            showTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { _ in present() }
        }
    }

    /// Keeps an open preview in step after windows close, minimise or move.
    func sync(with maps: [Engine.MiniMap]) {
        guard panel?.isVisible == true, let current = model.tile else { return }
        let ids = Set(current.windows.map(\.id))
        let updated = maps.lazy.flatMap(\.tiles).first { tile in tile.windows.contains { ids.contains($0.id) } }
        if let updated, !updated.windows.isEmpty {
            if updated != current { model.tile = updated }
        } else {
            hide()
        }
    }

    func hide() {
        showTimer?.invalidate()
        hideTimer?.invalidate()
        refreshTimer?.invalidate()
        refreshTimer = nil
        panel?.orderOut(nil)
        isHovered = false
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self, !self.isHovered else { return }
            self.hide()
        }
    }

    private func show(over bar: NSPanel, edge: SliderBarEdge) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = bar.screen?.frame ?? NSScreen.main?.frame ?? .zero
        model.aspect = Double(screen.width / max(screen.height, 1))
        let height = Self.width / CGFloat(model.aspect) + 44
        let mouseX = NSEvent.mouseLocation.x
        var x = mouseX - Self.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - Self.width - 8)
        let y = edge == .bottom ? bar.frame.maxY + 8 : bar.frame.minY - height - 8
        panel.setFrame(NSRect(x: x, y: y, width: Self.width, height: height), display: true)
        panel.orderFrontRegardless()
        refresh()
        if refreshTimer == nil {
            // Live: refresh the window images while the preview is open.
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.refresh() }
        }
    }

    private func refresh() {
        model.previewsAllowed = WindowThumbnails.isAllowed
        guard model.previewsAllowed, let tile = model.tile else { return }
        WindowThumbnails.capture(tile.windows.map(\.id)) { [weak self] images in
            self?.model.images.merge(images) { _, new in new }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = PreviewView(
            model: model,
            commands: { [weak self] in
                guard let self else { return WindowCommands() }
                var commands = self.commands
                let focus = commands.focus, rename = commands.rename, own = commands.ownSlide
                commands.focus = { [weak self] id in self?.hide(); focus(id) }
                commands.rename = { [weak self] id in self?.hide(); rename(id) }
                commands.ownSlide = { [weak self] id in self?.hide(); own(id) }
                return commands
            },
            hovering: { [weak self] inside in
                guard let self else { return }
                self.isHovered = inside
                if inside { self.hideTimer?.invalidate() } else { self.scheduleHide() }
            })
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}

/// A small label above the slider bar naming the workspace dot under the pointer.
final class NameTip {
    private var panel: NSPanel?
    private let model = Model()

    final class Model: ObservableObject {
        @Published var text = ""
        @Published var color = Color.accentColor
    }

    func show(_ text: String, color: Color, over bar: NSPanel, edge: SliderBarEdge) {
        model.text = text
        model.color = color
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: 140, height: 30)
        let x = NSEvent.mouseLocation.x - size.width / 2
        let y = edge == .bottom ? bar.frame.maxY + 6 : bar.frame.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 30),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: TipView(model: model))
        panel.contentView = host
        return panel
    }

    private struct TipView: View {
        @ObservedObject var model: Model

        var body: some View {
            HStack(spacing: 6) {
                Circle().fill(model.color).frame(width: 8, height: 8)
                Text(model.text).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .fixedSize()
        }
    }
}

private final class PreviewModel: ObservableObject {
    @Published var tile: Engine.MiniTile?
    @Published var number = 0
    @Published var images: [WindowID: NSImage] = [:]
    @Published var previewsAllowed = WindowThumbnails.isAllowed
    var aspect = 16.0 / 10.0
}

private struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    let commands: () -> WindowCommands
    let hovering: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tile = model.tile {
                HStack(spacing: 6) {
                    Text("Slide \(model.number)").font(.system(size: 12, weight: .semibold))
                    Text("\(tile.windows.count) \(tile.windows.count == 1 ? "window" : "windows") · \(tile.arrangement.title)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if !model.previewsAllowed {
                        LivePreviewsButton(style: .link) {}
                    }
                }
                GeometryReader { geometry in
                    let frames = tile.arrangement.unitFrames(count: tile.windows.count, split: tile.split)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(tile.windows.enumerated()), id: \.element.id) { index, window in
                            let unit = frames[index]
                            PreviewTile(window: window, image: model.images[window.id])
                                .frame(
                                    width: max(unit.width * geometry.size.width - 6, 10),
                                    height: max(unit.height * geometry.size.height - 6, 10))
                                .onTapGesture { commands().focus(window.id) }
                                .windowControls(window.id, commands())
                                .offset(x: unit.minX * geometry.size.width + 3, y: unit.minY * geometry.size.height + 3)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .onHover(perform: hovering)
    }
}

private struct PreviewTile: View {
    let window: Engine.MiniWindow
    let image: NSImage?
    @State private var hovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if let icon = AppIcons.icon(for: window.pid) {
                Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 4) {
                if image != nil, let icon = AppIcons.icon(for: window.pid) {
                    Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                }
                Text(window.title.isEmpty ? window.appName : window.title)
                    .font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(hovered ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: hovered ? 2 : 1))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: - Menu bar popover

/// What a left-click on the menu bar icon shows: the slider, the slides as
/// cards you can click through, and quick controls.
final class SliderPopover: NSObject, NSPopoverDelegate {
    struct Controls {
        var isPaused: () -> Bool
        var resetPairs: () -> Void
        var togglePause: () -> Void
        var openSettings: () -> Void
    }

    var mapProvider: () -> Engine.MiniMap? = { nil }
    var actions = SliderBarController.Actions(
        slide: { _, _ in }, endSlide: {}, focus: { _ in }, switchWorkspace: { _ in }, showOverview: {})
    var controls = Controls(isPaused: { false }, resetPairs: {}, togglePause: {}, openSettings: {})
    var updater: Updater?

    private let popover = NSPopover()
    private let model = SliderBarModel()
    private let paused = PausedState()

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if popover.contentViewController == nil {
            let close: () -> Void = { [weak self] in self?.popover.performClose(nil) }
            var wrapped = actions
            let focus = actions.focus
            let overview = actions.showOverview
            wrapped.focus = { id in
                close()
                focus(id)
            }
            wrapped.showOverview = {
                close()
                overview()
            }
            let controls = self.controls
            let view = SliderPopoverView(
                model: model, paused: paused, updater: updater ?? Updater(), actions: wrapped,
                resetPairs: { [weak self] in
                    controls.resetPairs()
                    self?.refresh()
                },
                togglePause: { [weak self] in
                    controls.togglePause()
                    self?.paused.value = controls.isPaused()
                },
                openSettings: {
                    close()
                    controls.openSettings()
                })
            popover.contentViewController = NSHostingController(rootView: view)
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
        }
        model.map = mapProvider()
        paused.value = controls.isPaused()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Keeps an open popover in step with the strip.
    func refresh() {
        guard popover.isShown else { return }
        model.map = mapProvider()
        paused.value = controls.isPaused()
    }
}

final class PausedState: ObservableObject {
    @Published var value = false
}

private struct SliderPopoverView: View {
    @ObservedObject var model: SliderBarModel
    @ObservedObject var paused: PausedState
    @ObservedObject var updater: Updater
    let actions: SliderBarController.Actions
    let resetPairs: () -> Void
    let togglePause: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("MacSlider").font(.headline)
                if let map = model.map {
                    Text(map.workspaceCount > 1 ? "Workspace \(map.workspace + 1) · \(map.tiles.count) slides"
                                                : "\(map.tiles.count) slides")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let release = updater.available {
                    Button {
                        updater.installAvailable()
                    } label: {
                        Label("Update to \(release.version)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(updater.isInstalling)
                    .help("Download, install and relaunch — your windows stay where they are")
                }
                Button(action: resetPairs) { Image(systemName: "wand.and.stars") }
                    .help("Reset to smart pairs: windows of the same app together")
                Button(action: togglePause) {
                    Image(systemName: paused.value ? "play.fill" : "pause.fill")
                }
                .help(paused.value ? "Resume tiling" : "Pause tiling")
                Button(action: actions.showOverview) { Image(systemName: "square.grid.3x2") }
                    .help("Overview")
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .help("Settings")
            }
            .buttonStyle(.borderless)

            SliderBarView(model: model, actions: actions) {}
                .frame(height: 52)

            if let map = model.map, !map.tiles.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(map.tiles.enumerated()), id: \.element.id) { number, tile in
                                SlideCard(number: number + 1, tile: tile)
                                    .id(tile.id)
                                    .onTapGesture {
                                        if let window = tile.windows.first { actions.focus(window.id) }
                                    }
                            }
                        }
                        .padding(.vertical, 2)
                        .environment(\.layoutDirection, map.isRightToLeft ? .rightToLeft : .leftToRight)
                    }
                    .onAppear {
                        if let focused = map.tiles.first(where: \.isFocused) { proxy.scrollTo(focused.id, anchor: .center) }
                    }
                }
            } else {
                Text("No windows on this workspace yet.").font(.callout).foregroundStyle(.secondary)
            }

            Text("Drag the slider to move · click a slide to jump · right-click the icon for the full menu")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 560)
    }
}

/// A slide in the popover: its layout outline, app icons and first window's title.
private struct SlideCard: View {
    let number: Int
    let tile: Engine.MiniTile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(tile.isFocused ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08))
                if tile.windows.count > 1 {
                    TileOutlines(frames: tile.arrangement.unitFrames(count: tile.windows.count, split: tile.split))
                        .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                        .padding(4)
                }
                HStack(spacing: 3) {
                    ForEach(Array(Set(tile.windows.map(\.pid))).sorted().prefix(4), id: \.self) { pid in
                        if let icon = AppIcons.icon(for: pid) {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        }
                    }
                }
            }
            .frame(width: 120, height: 70)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(tile.isFocused ? Color.accentColor : Color.clear, lineWidth: 2))
            HStack(spacing: 4) {
                Text("\(number)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(tile.windows.first.map { $0.title.isEmpty ? $0.appName : $0.title } ?? "")
                    .font(.caption).lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
        }
        .contentShape(Rectangle())
        .help(tile.windows.map { $0.title.isEmpty ? $0.appName : "\($0.appName) — \($0.title)" }.joined(separator: "\n"))
    }
}
#endif
