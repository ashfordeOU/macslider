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
    /// Opens (true) or closes (false) three practice windows to try the moves on.
    var practiceWindows: (Bool) -> Void = { _ in }
    @State private var practising = false
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Welcome to \(Brand.name)").font(.title).fontWeight(.semibold)
                        Text(Brand.maker).font(.title3).foregroundStyle(.secondary)
                    }
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
                        Text(L("1. Allow Accessibility")).fontWeight(.medium)
                        Text(
                            trusted
                                ? "Done. Monorail can now arrange your windows."
                                : "macOS needs your permission before any app can move other apps’ windows. Monorail asks for nothing else, works offline and collects no data."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        if !trusted {
                            Button(L("Open Accessibility Settings")) {
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
                    Text(L("2. Choose how you see your slides")).fontWeight(.medium)
                    HStack(spacing: 12) {
                        ViewChoice(
                            title: "Slider bar + menu bar icon",
                            detail: "A bar of your slides along the bottom of the screen.",
                            withBar: true,
                            selected: store.settings.sliderBar != .off
                        ) { store.settings.sliderBar = .always }
                        ViewChoice(
                            title: "Menu bar icon only",
                            detail: "Windows reach right down to the Dock. Click the icon for your slides.",
                            withBar: false,
                            selected: store.settings.sliderBar == .off
                        ) { store.settings.sliderBar = .off }
                    }
                    Text("You can switch any time in Settings → Appearance.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("3. Get around")).fontWeight(.medium)
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
                        Text(L("4. Practice")).fontWeight(.medium)
                        Spacer()
                        Text("\(practice.done.count) of \(PracticeTracker.tasks.count)")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Open two or three windows, then try each move. They tick off as you go.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button(practising ? L("Close demo windows") : L("Practice with demo windows")) {
                        practising.toggle()
                        practiceWindows(practising)
                    }
                    .help("Three of Monorail’s own windows to practise on, so your real work stays put")
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
                Button(trusted ? L("Start sliding") : L("Continue without permission")) { onFinish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onReceive(timer) { _ in trusted = Accessibility.isTrusted(prompt: false) }
    }
}

/// One of the two ways to see your slides, drawn as a little screen.
private struct ViewChoice: View {
    let title: String
    let detail: String
    let withBar: Bool
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 8) {
                MiniScreen(withBar: withBar).frame(height: 92)
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Text(title).fontWeight(.medium)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(selected ? 0.08 : 0.03)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A sketch of a Mac screen: menu bar, two windows side by side, the Dock,
/// and either the slider bar above the Dock or the menu bar icon's panel.
private struct MiniScreen: View {
    let withBar: Bool

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            let menu: CGFloat = 9, dock: CGFloat = 12, bar: CGFloat = withBar ? 13 : 0, gap: CGFloat = 4
            let windowsTop = menu + gap
            let windowsBottom = h - dock - gap - (withBar ? bar + gap : 0)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.2, green: 0.25, blue: 0.5), Color(red: 0.45, green: 0.2, blue: 0.45)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: w, height: menu)
                // The Monorail icon in the menu bar.
                RoundedRectangle(cornerRadius: 1.5).fill(Color.white)
                    .frame(width: 10, height: 5).offset(x: w * 0.68, y: 2)
                ForEach(0..<2, id: \.self) { i in
                    let width = (w - gap * 3) / 2
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(i == 0 ? 0.9 : 0.75))
                        .frame(width: width, height: windowsBottom - windowsTop)
                        .offset(x: gap + CGFloat(i) * (width + gap), y: windowsTop)
                }
                if withBar {
                    Capsule().fill(Color.black.opacity(0.45))
                        .overlay(HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i == 1 ? Color.accentColor : Color.white.opacity(0.5))
                                    .frame(width: 12, height: 6)
                            }
                        })
                        .frame(width: w * 0.62, height: bar)
                        .offset(x: w * 0.19, y: windowsBottom + gap)
                } else {
                    // The slider panel hanging from the icon.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.6))
                        .overlay(HStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i == 1 ? Color.accentColor : Color.white.opacity(0.5))
                                    .frame(width: 10, height: 7)
                            }
                        })
                        .frame(width: 62, height: 20)
                        .offset(x: w * 0.68 + 5 - 31, y: menu + 2)
                        .shadow(radius: 3)
                }
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.35))
                    .frame(width: w * 0.5, height: dock - 4).offset(x: w * 0.25, y: h - dock + 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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
