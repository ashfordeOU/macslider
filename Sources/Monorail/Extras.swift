#if os(macOS)
import AppKit
import MonorailCore
import SwiftUI

/// Hold ⌃⌥ for a moment (or press ⌃⌥⇧/) and every shortcut appears; let go and it's gone.
final class CheatSheet {
    private var panel: NSPanel?
    private var holdTimer: Timer?
    private var keyPressed = false
    private(set) var isShown = false
    var keymap: () -> Keymap = { .default }

    /// Modifier changes: ⌃⌥ held alone for 0.9 s shows the sheet.
    func modifiersChanged(_ modifiers: Modifiers, enabled: Bool) {
        holdTimer?.invalidate()
        if modifiers == [.control, .option] && enabled {
            keyPressed = false
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
                guard let self, !self.keyPressed else { return }
                self.show()
            }
        } else if isShown {
            hide()
        }
    }

    /// Any key press cancels a pending sheet (you were using a shortcut).
    func keyWasPressed() {
        keyPressed = true
        holdTimer?.invalidate()
    }

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        let groups = Self.groups.map { title, actions in
            (title, actions.compactMap { action -> (String, String)? in
                guard let shortcut = keymap().shortcuts(for: action).first else { return nil }
                return (action.title, shortcut.displayString)
            })
        }.filter { !$0.1.isEmpty }
        let view = CheatSheetView(groups: groups)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let panel = self.panel ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .popUpMenu
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
            return panel
        }()
        self.panel = panel
        panel.contentView = host
        let width = min(size.width, area.width - 40), height = min(size.height, area.height - 40)
        panel.setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        isShown = true
    }

    func hide() {
        holdTimer?.invalidate()
        panel?.orderOut(nil)
        isShown = false
    }

    private static let groups: [(String, [Action])] = [
        ("Move around", [.focusLeft, .focusRight, .focusUp, .focusDown, .windowHints, .lastWindow, .cycleAppWindows, .jumpToMark]),
        ("Move windows", [.moveLeft, .moveRight, .swapWithRecent, .moveToNextWorkspace, .sendToNextDisplay, .toggleFloat]),
        ("Slides", [.cycleLayout, .rotateSlide, .flipSlide, .makeMain, .toggleTabbed, .regroup, .balanceSizes, .zoomTile]),
        ("Width", [.cycleWidth, .narrower, .wider, .toggleFullWidth, .center, .resizeMode]),
        ("Workspaces", [.workspace1, .moveToWorkspace1, .nextWorkspace, .workspaceBackAndForth, .nextProfile]),
        ("See everything", [.overview, .stripZoom, .windowSwitcher, .commandPalette, .appOverview]),
        ("Modes", [.toggleFocusMode, .soloMode, .presentationMode, .toggleScratchpad, .showDesktop, .radialMenu]),
        ("Undo and more", [.undo, .redo, .takeSnapshot, .screenshotSlide, .togglePause]),
    ]
}

private struct CheatSheetView: View {
    let groups: [(String, [(String, String)])]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Monorail").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("shortcuts").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Text("Let go of ⌃⌥ to close · change them in Settings → Shortcuts").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top),
                                GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 16) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.0.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        ForEach(Array(group.1.enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: 6) {
                                Text(entry.1)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
                                Text(entry.0).font(.system(size: 11)).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 980)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// The workspace's name, big, for a moment after switching.
final class WorkspaceHUD {
    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(name: String, note: String? = nil, index: Int, count: Int) {
        let host = NSHostingView(rootView: WorkspaceHUDView(name: name, note: note, index: index, count: count))
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let panel = self.panel ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .popUpMenu
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
            return panel
        }()
        self.panel = panel
        panel.contentView = host
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height),
                       display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil) })
        }
    }
}

private struct WorkspaceHUDView: View {
    let name: String
    var note: String?
    let index: Int
    let count: Int

    var body: some View {
        VStack(spacing: 10) {
            Text(name).font(.system(size: 30, weight: .bold, design: .rounded))
            if let note { Text(note).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420) }
            HStack(spacing: 7) {
                ForEach(0..<max(count, 1), id: \.self) { i in
                    Circle().fill(i == index ? WorkspaceColor.color(i) : Color.primary.opacity(0.25)).frame(width: 9, height: 9)
                }
            }
        }
        .padding(.horizontal, 34).padding(.vertical, 22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workspace \(name)")
    }
}
#endif
