#if os(macOS)
import AppKit
import Combine
import MonorailCore
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
        /// Hold ⌥ over a slide to peek at it; let go to slide back.
        var peek: (_ column: Int, _ displayUUID: String) -> Void = { _, _ in }
        var endPeek: () -> Void = {}
        /// Swipe up on the bar to park the workspace, down to bring it back.
        var park: (Int) -> Void = { _ in }
        var unpark: (Int) -> Void = { _ in }
    }

    var edge: SliderBarEdge = .bottom
    var mapsProvider: () -> [Engine.MiniMap] = { [] }
    var actions = Actions(slide: { _, _ in }, endSlide: {}, focus: { _ in }, switchWorkspace: { _ in }, showOverview: {})

    private var bars: [String: (panel: NSPanel, model: SliderBarModel)] = [:]
    private var hideTimer: Timer?
    private let preview = SlidePreview()
    private let tip = NameTip()
    private var subscriptions: [AnyCancellable] = []
    private lazy var peekWatcher = PeekWatcher(
        models: { [weak self] in self?.bars.values.map(\.model) ?? [] },
        peek: { [weak self] column, uuid in self?.actions.peek(column, uuid) },
        endPeek: { [weak self] in self?.actions.endPeek() })
    var peekEnabled: Bool {
        get { peekWatcher.isEnabled }
        set { peekWatcher.isEnabled = newValue }
    }
    /// A smaller bar, and window titles on its tiles.
    var compact = false
    var showTitles = false
    private var height: CGFloat { compact ? 40 : 52 }
    private static let margin: CGFloat = 6

    /// Refreshes the bars. Called whenever the strips change.
    func update() {
        let maps = mapsProvider()
        guard maps.contains(where: { $0.barMode != .off }) else {
            hideAll(animated: false)
            return
        }
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
            if bar.model.showTitles != showTitles { bar.model.showTitles = showTitles }
            if bar.model.map != map {
                changed = changed || bar.model.map?.viewportX != map.viewportX
                    || bar.model.map?.tiles != map.tiles || bar.model.map?.workspace != map.workspace
                bar.model.map = map
            }
            position(bar.panel, for: map)
            let empty = map.tiles.isEmpty
            if map.barMode == .off {
                bar.panel.orderOut(nil)
            } else if map.barMode == .always {
                show(bar.panel)
            } else if empty {
                bar.panel.orderOut(nil)
            }
        }
        if changed {
            let moving = bars.values.filter {
                $0.model.map?.barMode == .whileMoving && !($0.model.map?.tiles.isEmpty ?? true)
            }
            for bar in moving { show(bar.panel) }
            if !moving.isEmpty { scheduleHide() }
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
            guard let self else { return }
            // Stay while the pointer is on a bar or its preview, or a drag is in progress.
            if self.preview.isHovered || self.bars.values.contains(where: { $0.model.isHovering || $0.model.isDragging }) {
                self.scheduleHide()
            } else {
                for bar in self.bars.values where bar.model.map?.barMode == .whileMoving {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.25
                        bar.panel.animator().alphaValue = 0
                    }, completionHandler: { bar.panel.orderOut(nil) })
                }
                self.preview.hide()
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
            : screen.maxY - height - Self.margin
        let frame = NSRect(x: screen.midX - width / 2, y: y, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func makeBar(for uuid: String) -> (panel: NSPanel, model: SliderBarModel) {
        let model = SliderBarModel()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: height),
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
        peekWatcher.watch(model)
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

/// Peek: hold ⌥ while the pointer is on a slide in the slider and the strip
/// slides to show it; let go and it slides back. Click while peeking to stay.
final class PeekWatcher {
    var isEnabled = true
    private let models: () -> [SliderBarModel]
    private let peek: (Int, String) -> Void
    private let endPeek: () -> Void
    private var monitors: [Any] = []
    private var subscriptions: [AnyCancellable] = []
    private(set) var isPeeking = false

    init(models: @escaping () -> [SliderBarModel], peek: @escaping (Int, String) -> Void, endPeek: @escaping () -> Void) {
        self.models = models
        self.peek = peek
        self.endPeek = endPeek
        let handler: (NSEvent) -> Void = { [weak self] event in self?.flagsChanged(event.modifierFlags) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Follows the pointer from slide to slide while ⌥ is held.
    func watch(_ model: SliderBarModel) {
        model.$hoveredTile
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self, weak model] tile in
                guard let self, self.isPeeking, let tile, let uuid = model?.map?.displayUUID else { return }
                self.peek(tile.id, uuid)
            }
            .store(in: &subscriptions)
    }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        let optionOnly = flags.intersection([.option, .command, .control, .shift]) == .option
        if optionOnly, isEnabled, !isPeeking,
            let model = models().first(where: { $0.hoveredTile != nil }), let tile = model.hoveredTile,
            let uuid = model.map?.displayUUID
        {
            isPeeking = true
            peek(tile.id, uuid)
        } else if !optionOnly, isPeeking {
            isPeeking = false
            endPeek()
        }
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
    /// Window titles (or the slide's name) on the tiles.
    @Published var showTitles = false
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
    /// Set when a drag on the track goes up or down instead of sideways.
    @State private var verticalSwipe = false

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
                                Button("Rename “\(name)”") { actions.renameWorkspace(index) }
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

    /// The window under a click on the track: the slide under the pointer, then
    /// the tile within it (left or right half of a pair, a cell of a grid…).
    private func window(
        at point: CGPoint, map: Engine.MiniMap, lower: Double, span: Double, scale: Double, height: Double
    ) -> WindowID? {
        let x = Double(point.x)
        func left(_ tile: Engine.MiniTile) -> Double {
            trackX(tile.x, width: tile.width, lower: lower, span: span, scale: scale, map: map)
        }
        let hit = map.tiles.first { x >= left($0) - 2 && x <= left($0) + $0.width * scale + 2 }
        let nearest = map.tiles.min { abs(left($0) + $0.width * scale / 2 - x) < abs(left($1) + $1.width * scale / 2 - x) }
        guard let tile = hit ?? nearest else { return nil }
        var ux = min(max((x - left(tile)) / max(tile.width * scale, 1), 0), 0.999)
        let uy = min(max((Double(point.y) - 4) / max(height - 8, 1), 0), 0.999)
        if map.isRightToLeft { ux = 1 - ux }
        let frames = tile.arrangement.unitFrames(count: tile.windows.count, split: tile.split, rows: tile.customRows)
        let index = frames.firstIndex { $0.contains(x: ux, y: uy) } ?? 0
        return tile.windows.indices.contains(index) ? tile.windows[index].id : tile.windows.first?.id
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
                    TileView(tile: tile, height: size.height - 8, showTitle: model.showTitles)
                        .frame(width: max(tile.width * scale - 3, 6), height: size.height - 8)
                        .offset(x: trackX(tile.x, width: tile.width, lower: lower, span: span, scale: scale, map: map) + 1.5, y: 4)
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
            // One gesture for both clicks and drags, so a click with a little
            // pointer movement still counts as a click.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !verticalSwipe else { return }
                        guard dragScale != nil || hypot(value.translation.width, value.translation.height) > 4 else {
                            return
                        }
                        if dragScale == nil, abs(value.translation.height) > abs(value.translation.width) * 1.3 {
                            verticalSwipe = true
                            return
                        }
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
                    .onEnded { value in
                        if verticalSwipe {
                            // Swipe up parks the workspace in the Dock; swipe down brings it back.
                            if value.translation.height < -16 {
                                actions.park(map.workspace)
                            } else if value.translation.height > 16 {
                                actions.unpark(map.workspace)
                            }
                            verticalSwipe = false
                            onInteraction()
                            return
                        }
                        if dragScale == nil {
                            // A click: jump to the window under the pointer.
                            if let id = window(at: value.location, map: map, lower: lower, span: span, scale: scale,
                                               height: Double(size.height)) {
                                actions.focus(id)
                            }
                        } else {
                            actions.endSlide()
                        }
                        dragScale = nil
                        model.isDragging = false
                        onInteraction()
                    }
            )
        }
    }
}

private struct TileView: View {
    let tile: Engine.MiniTile
    let height: CGFloat
    var showTitle = false

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
                TileOutlines(frames: tile.arrangement.unitFrames(count: tile.windows.count, split: tile.split, rows: tile.customRows))
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    .padding(3)
            }
            HStack(spacing: 2) {
                ForEach(icons.prefix(showTitle ? 1 : 4), id: \.self) { pid in
                    if let icon = AppIcons.icon(for: pid) {
                        Image(nsImage: icon).resizable().frame(width: iconSize, height: iconSize)
                    }
                }
                if showTitle || tile.name != nil {
                    Text(tile.name ?? tile.windows.first.map { $0.title.isEmpty ? $0.appName : $0.title } ?? "")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if tile.windows.count > 1 {
                    Text("\(tile.windows.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if tile.isLocked {
                    Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 3)
        }
        .overlay(alignment: .topTrailing) {
            if tile.windows.contains(where: \.needsAttention) {
                Circle().fill(Color.red).frame(width: 6, height: 6).padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.windows.map(\.appName).joined(separator: " and ")
            + (tile.windows.contains(where: \.needsAttention) ? ", needs attention" : ""))
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
                    let frames = tile.arrangement.unitFrames(count: tile.windows.count, split: tile.split, rows: tile.customRows)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(tile.windows.enumerated()), id: \.element.id) { index, window in
                            let unit = frames[index]
                            // 8pt between tiles, each clipped to its own rounded rectangle.
                            PreviewTile(window: window, image: model.images[window.id])
                                .frame(
                                    width: max(unit.width * geometry.size.width - 8, 10),
                                    height: max(unit.height * geometry.size.height - 8, 10))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { commands().focus(window.id) }
                                .windowControls(window.id, commands())
                                .offset(x: unit.minX * geometry.size.width + 4, y: unit.minY * geometry.size.height + 4)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(window.appName), \(window.title)")
                                .accessibilityAddTraits(.isButton)
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
                // Fill the tile exactly: never wider than it, whatever the window's shape.
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                        .clipped()
                }
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
/// It hangs right under the icon, like Control Center, and closes when you
/// click anywhere else.
final class SliderPopover {
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

    private var panel: NSPanel?
    private var host: NSView?
    private var clickMonitor: Any?
    private weak var anchor: NSStatusBarButton?
    private let model = SliderBarModel()
    private lazy var peekWatcher = PeekWatcher(
        models: { [weak self] in self.map { [$0.model] } ?? [] },
        peek: { [weak self] column, uuid in self?.actions.peek(column, uuid) },
        endPeek: { [weak self] in self?.actions.endPeek() })
    var peekEnabled: Bool {
        get { peekWatcher.isEnabled }
        set { peekWatcher.isEnabled = newValue }
    }
    private let paused = PausedState()

    /// Space between the menu bar and the panel.
    private static let gap: CGFloat = 6

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isShown {
            close()
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        anchor = button
        model.map = mapProvider()
        paused.value = controls.isPaused()
        place()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        // Clicks in other apps close it; clicks in the panel are local and don't.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.close()
        }
    }

    func close() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel?.orderOut(nil)
    }

    /// Keeps an open panel in step with the strip.
    func refresh() {
        guard isShown else { return }
        model.map = mapProvider()
        paused.value = controls.isPaused()
        DispatchQueue.main.async { [weak self] in self?.place() }
    }

    /// Sizes the panel to its content and hangs it just below the icon,
    /// centred on it but kept on screen.
    private func place() {
        guard let panel, let host, let button = anchor, let window = button.window else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.screens.first { $0.frame.contains(icon.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? icon
        var x = icon.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let top = min(icon.minY, visible.maxY) - Self.gap
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func makePanel() -> NSPanel {
        let close: () -> Void = { [weak self] in self?.close() }
        var wrapped = actions
        let focus = actions.focus
        let overview = actions.showOverview
        let rename = actions.renameWorkspace
        wrapped.focus = { id in
            close()
            focus(id)
        }
        wrapped.showOverview = {
            close()
            overview()
        }
        wrapped.renameWorkspace = { index in
            close()
            rename(index)
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

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]

        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor.separatorColor.cgColor
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass
        self.host = host
        peekWatcher.watch(model)
        return panel
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Brand.name).font(.headline)
                    Text(Brand.maker).font(.caption).foregroundStyle(.secondary)
                }
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
                    TileOutlines(frames: tile.arrangement.unitFrames(count: tile.windows.count, split: tile.split, rows: tile.customRows))
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
