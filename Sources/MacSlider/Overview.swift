#if os(macOS)
import AppKit
import MacSliderCore
import SwiftUI
import UniformTypeIdentifiers

final class OverviewModel: ObservableObject {
    @Published var strips: [Engine.OverviewStrip] = []
    @Published var thumbnails: [WindowID: NSImage] = [:]
    @Published var previewsAllowed = WindowThumbnails.isAllowed

    func loadThumbnails() {
        previewsAllowed = WindowThumbnails.isAllowed
        guard previewsAllowed else { return }
        let ids = strips.flatMap { $0.columns.flatMap { $0.windows.map(\.id) } }
        WindowThumbnails.capture(ids) { [weak self] images in self?.thumbnails = images }
    }
}

/// Drag payloads: a window ("w:<id>") or a whole column ("c:<row>:<column>").
private enum DragItem {
    case window(WindowID)
    case column(row: Int, column: Int)

    var string: String {
        switch self {
        case .window(let id): return "w:\(id)"
        case .column(let row, let column): return "c:\(row):\(column)"
        }
    }

    init?(_ string: String) {
        let parts = string.split(separator: ":")
        if parts.count == 2, parts[0] == "w", let id = WindowID(parts[1]) {
            self = .window(id)
        } else if parts.count == 3, parts[0] == "c", let row = Int(parts[1]), let column = Int(parts[2]) {
            self = .column(row: row, column: column)
        } else {
            return nil
        }
    }

    var provider: NSItemProvider { NSItemProvider(object: string as NSString) }

    static func load(_ providers: [NSItemProvider], _ completion: @escaping (DragItem) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let item = DragItem(string) else { return }
            DispatchQueue.main.async { completion(item) }
        }
        return true
    }
}

struct OverviewActions {
    var focus: (WindowID) -> Void
    var show: (StripKey) -> Void
    var moveWindow: (WindowID, StripKey, _ column: Int?, _ newColumnAt: Int?) -> Void
    var moveColumn: (_ from: Int, _ to: Int, StripKey) -> Void
    var resetPairs: () -> Void
    var close: () -> Void
    var renameWorkspace: (Int) -> Void = { _ in }
    var commands = WindowCommands()
}

/// The overview's backdrop: a deep, colourful gradient with soft glows and a
/// fine dot pattern, over a blur of the desktop.
private struct OverviewBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.09, blue: 0.36),
                    Color(red: 0.36, green: 0.13, blue: 0.5),
                    Color(red: 0.05, green: 0.3, blue: 0.46),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .opacity(0.9)
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    Circle().fill(Color(red: 1, green: 0.38, blue: 0.62).opacity(0.35))
                        .frame(width: size.width * 0.45).blur(radius: 140)
                        .position(x: size.width * 0.12, y: size.height * 0.1)
                    Circle().fill(Color(red: 0.2, green: 0.8, blue: 0.86).opacity(0.3))
                        .frame(width: size.width * 0.5).blur(radius: 160)
                        .position(x: size.width * 0.9, y: size.height * 0.92)
                    Circle().fill(Color(red: 1, green: 0.58, blue: 0.27).opacity(0.18))
                        .frame(width: size.width * 0.3).blur(radius: 120)
                        .position(x: size.width * 0.75, y: size.height * 0.15)
                }
            }
            Canvas { context, size in
                let spacing: CGFloat = 26
                var y: CGFloat = spacing / 2
                while y < size.height {
                    var x: CGFloat = spacing / 2
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)),
                                     with: .color(.white.opacity(0.07)))
                        x += spacing
                    }
                    y += spacing
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct OverviewView: View {
    @ObservedObject var model: OverviewModel
    let actions: OverviewActions

    var body: some View {
        ZStack {
            OverviewBackground()
                .contentShape(Rectangle())
                .onTapGesture { actions.close() }
            VStack(alignment: .leading, spacing: 18) {
                header
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(model.strips.enumerated()), id: \.element.id) { row, strip in
                            StripRow(row: row, strip: strip, model: model, actions: actions)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(36)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Overview").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text("Click to jump · drag a window onto a slide to pair it (your pairings stay until you reset) · drag between slides to give it its own · drag ≡ to reorder · esc to close")
                .font(.callout).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button {
                actions.resetPairs()
            } label: {
                Label("Reset to smart pairs", systemImage: "wand.and.stars")
            }
            .help("Put windows of the same app back together, undoing your own pairings")
            if !model.previewsAllowed {
                LivePreviewsButton { model.loadThumbnails() }
            }
        }
    }
}

private struct StripRow: View {
    let row: Int
    let strip: Engine.OverviewStrip
    @ObservedObject var model: OverviewModel
    let actions: OverviewActions
    private let height: CGFloat = 190

    private var color: Color { WorkspaceColor.color(strip.workspace) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    actions.show(strip.key)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(color).frame(width: 10, height: 10)
                            .shadow(color: color.opacity(0.8), radius: strip.isActive ? 6 : 0)
                        Text(strip.title).font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("\(strip.columns.count) \(strip.columns.count == 1 ? "slide" : "slides")")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        if strip.isActive {
                            Text("Current").font(.caption.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(color.opacity(0.35)))
                        }
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename “\(strip.title)”…") { actions.renameWorkspace(strip.workspace) }
                }
                Button {
                    actions.renameWorkspace(strip.workspace)
                } label: {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .help("Rename this workspace")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    DropSlot(row: row, index: 0, strip: strip, actions: actions, height: height)
                    ForEach(strip.columns) { column in
                        ColumnCard(row: row, strip: strip, column: column, model: model, actions: actions,
                                   height: height)
                        DropSlot(row: row, index: column.id + 1, strip: strip, actions: actions, height: height)
                    }
                    if strip.columns.isEmpty {
                        Text("Empty — drop a window here")
                            .font(.callout).foregroundStyle(.white.opacity(0.5))
                            .frame(width: 260, height: height)
                            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5])))
                    }
                }
                // A right-to-left strip reads right to left here too.
                .environment(\.layoutDirection, strip.isRightToLeft ? .rightToLeft : .leftToRight)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [color.opacity(strip.isActive ? 0.22 : 0.12), Color.white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(color.opacity(strip.isActive ? 0.85 : 0.3), lineWidth: strip.isActive ? 2 : 1))
        .shadow(color: strip.isActive ? color.opacity(0.35) : .clear, radius: 18)
    }
}

/// The gap between two slides: dropping a window here gives it a column of its
/// own; dropping a slide here moves the slide.
private struct DropSlot: View {
    let row: Int
    let index: Int
    let strip: Engine.OverviewStrip
    let actions: OverviewActions
    let height: CGFloat
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(targeted ? Color.accentColor : Color.clear)
            .frame(width: targeted ? 10 : 14, height: height)
            .padding(.horizontal, targeted ? 4 : 2)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.text], isTargeted: $targeted) { providers in
                DragItem.load(providers) { item in
                    switch item {
                    case .window(let id):
                        actions.moveWindow(id, strip.key, nil, index)
                    case .column(let sourceRow, let column) where sourceRow == row:
                        actions.moveColumn(column, index, strip.key)
                    default:
                        break
                    }
                }
            }
    }
}

private struct ColumnCard: View {
    let row: Int
    let strip: Engine.OverviewStrip
    let column: Engine.OverviewColumn
    @ObservedObject var model: OverviewModel
    let actions: OverviewActions
    let height: CGFloat
    @State private var targeted = false

    private var width: CGFloat {
        max(90, CGFloat(column.width * strip.aspectRatio) * (height - 22))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                if column.pin != nil { Image(systemName: "pin.fill") }
                if column.isTabbed {
                    Image(systemName: "menubar.rectangle")
                } else if column.windows.count > 1 {
                    Image(systemName: column.arrangement.symbol)
                }
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.7))
            .frame(height: 14)
            .contentShape(Rectangle())
            .onDrag { DragItem.column(row: row, column: column.id).provider }
            .help("Drag to reorder this slide")

            tiles
                .frame(width: width, height: height - 22)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            targeted ? Color.white : (column.isFocused ? WorkspaceColor.color(strip.workspace) : Color.clear),
                            lineWidth: targeted ? 3 : 2))
        }
        .onDrop(of: [UTType.text], isTargeted: $targeted) { providers in
            DragItem.load(providers) { item in
                if case .window(let id) = item { actions.moveWindow(id, strip.key, column.id, nil) }
            }
        }
    }

    /// The column's windows drawn where they really sit: the same unit
    /// rectangles the layout uses, mirrored for a right-to-left strip.
    @ViewBuilder private var tiles: some View {
        let windows = column.windows
        if column.isTabbed {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(windows) { window in
                        Text(window.appName).font(.system(size: 9)).lineLimit(1)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                    }
                }
                .foregroundStyle(.white)
                if let first = windows.first(where: \.isFocused) ?? windows.first { tile(first) }
            }
            .padding(4)
        } else {
            GeometryReader { geometry in
                let frames = column.arrangement.unitFrames(count: windows.count, split: column.split)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        let unit = frames[index]
                        let x = strip.isRightToLeft ? 1 - unit.maxX : unit.minX
                        tile(window)
                            .frame(
                                width: max(unit.width * geometry.size.width - 4, 4),
                                height: max(unit.height * geometry.size.height - 4, 4))
                            .offset(x: x * geometry.size.width + 2, y: unit.minY * geometry.size.height + 2)
                    }
                }
            }
            .padding(2)
        }
    }

    private func tile(_ window: Engine.WindowSummary) -> some View {
        WindowTile(window: window, thumbnail: model.thumbnails[window.id])
            .onTapGesture { actions.focus(window.id) }
            .windowControls(window.id, actions.commands)
            .onDrag { DragItem.window(window.id).provider }
    }
}

private struct WindowTile: View {
    let window: Engine.WindowSummary
    let thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.18))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 4) {
                if thumbnail != nil, let icon = window.icon {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                Text(window.title.isEmpty ? window.appName : window.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(window.isFocused ? Color.accentColor : Color.white.opacity(hovering ? 0.6 : 0.12),
                              lineWidth: window.isFocused ? 2 : 1))
        .onHover { hovering = $0 }
    }
}

/// A full-screen, key-capable panel for the overview.
final class OverviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onEscape: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape || event.keyCode == KeyCode.returnKey {
            onEscape()
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignKey() {
        super.resignKey()
        onEscape()
    }
}

final class OverviewController {
    private let model = OverviewModel()
    private var panel: OverviewPanel?
    private weak var engine: Engine?

    init(engine: Engine) {
        self.engine = engine
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        guard let engine else { return }
        model.strips = engine.overview()
        model.thumbnails = [:]
        model.loadThumbnails()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen { panel.setFrame(screen.frame, display: true) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    var commands = WindowCommands()
    var renameWorkspace: (Int) -> Void = { _ in }

    /// Window commands for overview tiles: they act, then refresh the overview.
    private func overviewCommands() -> WindowCommands {
        var commands = WindowCommands()
        commands.focus = { [weak self] id in
            self?.close()
            self?.engine?.focusAndReveal(id)
        }
        commands.close = { [weak self] id in
            self?.commands.close(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.refresh() }
        }
        commands.minimize = { [weak self] id in
            self?.commands.minimize(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.refresh() }
        }
        commands.fullScreen = { [weak self] id in
            self?.close()
            self?.commands.fullScreen(id)
        }
        commands.ownSlide = { [weak self] id in
            self?.commands.ownSlide(id)
            self?.refresh()
        }
        commands.rename = { [weak self] id in
            self?.close()
            self?.commands.rename(id)
        }
        commands.moveToWorkspace = { [weak self] id, index in
            self?.commands.moveToWorkspace(id, index)
            self?.refresh()
        }
        commands.workspaceNames = { [weak self] in self?.commands.workspaceNames() ?? [] }
        commands.currentWorkspace = { [weak self] id in self?.commands.currentWorkspace(id) }
        return commands
    }

    private func refresh() {
        guard let engine else { return }
        model.strips = engine.overview()
        model.loadThumbnails()
    }

    private func makePanel() -> OverviewPanel {
        let panel = OverviewPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        panel.onEscape = { [weak self] in self?.close() }

        let actions = OverviewActions(
            focus: { [weak self] id in
                self?.close()
                self?.engine?.focusAndReveal(id)
            },
            show: { [weak self] key in
                self?.close()
                self?.engine?.overviewShow(key)
            },
            moveWindow: { [weak self] id, key, column, newColumnAt in
                self?.engine?.overviewMove(id, to: key, column: column, newColumnAt: newColumnAt)
                self?.refresh()
            },
            moveColumn: { [weak self] from, to, key in
                self?.engine?.overviewMoveColumn(from: from, to: to, in: key)
                self?.refresh()
            },
            resetPairs: { [weak self] in
                self?.engine?.perform(.regroup)
                self?.refresh()
            },
            close: { [weak self] in self?.close() },
            renameWorkspace: { [weak self] index in
                self?.close()
                self?.renameWorkspace(index)
            },
            commands: overviewCommands()
        )
        // Frosted glass: blur whatever is behind the overview, then draw on top.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: OverviewView(model: model, actions: actions))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur
        return panel
    }
}
#endif
