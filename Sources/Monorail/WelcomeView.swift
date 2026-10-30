#if os(macOS)
import AppKit
import Combine
import MonorailCore
import SwiftUI

/// First-run tour: grant Accessibility, then learn the easy ways to get around.
/// Remembers which core moves the user has tried, for the practice pad.
final class PracticeTracker: ObservableObject {
    struct Task: Identifiable {
        var id: String { title }
        var title: String
        var actions: Set<Action>
        /// How to do it, shown in the coach card.
        var hint: String
    }

    static let tasks = [
        Task(title: "Slide to another window", actions: [.focusLeft, .focusRight],
             hint: "Tap the right ⌥ key, then press →   (or ⌃⌥→)"),
        Task(title: "Move a window along", actions: [.moveLeft, .moveRight],
             hint: "In slide mode press ⇧→   (or ⌃⌥⇧→)"),
        Task(title: "Change a window’s width", actions: [.cycleWidth, .cycleWidthBackward, .narrower, .wider],
             hint: "In slide mode press R   (or ⌃⌥R)"),
        Task(title: "Fill the screen", actions: [.toggleFullWidth],
             hint: "In slide mode press F   (or ⌃⌥F)"),
        Task(title: "Open the overview", actions: [.overview],
             hint: "In slide mode press O   (or ⌃⌥O)"),
    ]

    /// The first task not done yet.
    var next: Task? { Self.tasks.first { !done.contains($0.id) } }

    @Published private(set) var done: Set<String> = []

    func record(_ action: Action) {
        for task in Self.tasks where task.actions.contains(action) && !done.contains(task.id) {
            done.insert(task.id)
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var practice: PracticeTracker
    let onFinish: () -> Void
    @State private var trusted = Accessibility.isTrusted(prompt: false)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func shortcut(_ action: Action) -> String {
        store.settings.keymap.shortcuts(for: action).first?.displayString ?? "—"
    }

    private func tip(keys: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                .frame(width: 130, alignment: .leading)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Monorail").font(.title).fontWeight(.semibold)
                    Text("Your windows sit side by side on one endless strip. Nothing shrinks, nothing overlaps.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "lock.shield")
                        .font(.title2)
                        .foregroundStyle(trusted ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Allow Accessibility").fontWeight(.medium)
                        Text(
                            trusted
                                ? "Done. Monorail can now arrange your windows."
                                : "macOS needs your permission before any app can move other apps’ windows. Monorail asks for nothing else, works offline and collects no data."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        if !trusted {
                            Button("Open Accessibility Settings") {
                                _ = Accessibility.isTrusted(prompt: true)
                                if let url = URL(
                                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                                {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("2. Get around").fontWeight(.medium)
                    tip(
                        keys: store.settings.slideTrigger == .off ? "—" : "tap \(store.settings.slideTrigger.title)",
                        text: "Slide mode. Then just press ← → to slide between windows, ⇧← ⇧→ to move one, R for width, F to fill. Esc when done.")
                    tip(
                        keys: "\(store.settings.scrollModifier.symbols) + scroll",
                        text: "Hold \(store.settings.scrollModifier.symbols) and use the mouse wheel or trackpad. Each wheel notch moves one window.")
                    tip(keys: "menu bar", text: "Scroll over the menu bar, or click ‹ › next to the Monorail icon. No keys needed.")
                    tip(keys: "click", text: "Click any window, even the thin edge of one off-screen, to bring it into view.")
                    tip(keys: shortcut(.overview), text: "Overview: see every slide at once, click one to jump there, drag to rearrange.")
                    Text("Prefer shortcuts? \(shortcut(.focusLeft)) \(shortcut(.focusRight)) focus, \(shortcut(.cycleWidth)) width, \(shortcut(.toggleFullWidth)) fill. All of them can be changed in Settings.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("3. Practice").fontWeight(.medium)
                        Spacer()
                        Text("\(practice.done.count) of \(PracticeTracker.tasks.count)")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Open two or three windows, then try each move. They tick off as you go.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(PracticeTracker.tasks) { task in
                        HStack(spacing: 8) {
                            Image(systemName: practice.done.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(practice.done.contains(task.id) ? Color.green : Color.secondary)
                            Text(task.title)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                Text("Every shortcut can be changed in Settings.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(trusted ? "Start sliding" : "Continue without permission") { onFinish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onReceive(timer) { _ in trusted = Accessibility.isTrusted(prompt: false) }
    }
}

/// Coach tips: while the welcome tour is open, a card at the bottom of the
/// screen shows the next practice step and how to do it, live.
final class CoachTips {
    private var panel: NSPanel?
    private var subscription: AnyCancellable?

    func start(_ practice: PracticeTracker) {
        let panel = self.panel ?? makePanel(practice)
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        subscription = practice.$done.receive(on: DispatchQueue.main).sink { [weak self] done in
            guard done.count == PracticeTracker.tasks.count else { return }
            // All done: let the card say so, then go.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self?.stop() }
        }
    }

    func stop() {
        subscription = nil
        panel?.orderOut(nil)
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let size = NSSize(width: 560, height: 92)
        panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.minY + 90, width: size.width, height: size.height), display: true)
    }

    private func makePanel(_ practice: PracticeTracker) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 92),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CoachView(practice: practice))
        return panel
    }

    private struct CoachView: View {
        @ObservedObject var practice: PracticeTracker

        var body: some View {
            let total = PracticeTracker.tasks.count
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(red: 0.96, green: 0.38, blue: 0.44))
                    if let next = practice.next, let index = PracticeTracker.tasks.firstIndex(where: { $0.id == next.id }) {
                        Text("\(index + 1)/\(total)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    if let next = practice.next {
                        Text("Try it: \(next.title.lowercased())").font(.system(size: 15, weight: .semibold))
                        Text(next.hint).font(.system(size: 13)).foregroundStyle(.secondary)
                    } else {
                        Text("All done. You’re ready to slide!").font(.system(size: 15, weight: .semibold))
                        Text("Every shortcut is in the menu bar under Keyboard Shortcuts.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(width: 560, height: 92)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .animation(.easeOut(duration: 0.2), value: practice.done)
        }
    }
}
#endif
