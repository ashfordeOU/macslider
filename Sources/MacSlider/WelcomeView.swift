#if os(macOS)
import AppKit
import MacSliderCore
import SwiftUI

/// First-run tour: grant Accessibility, then learn the five core shortcuts.
struct WelcomeView: View {
    @ObservedObject var store: SettingsStore
    let onFinish: () -> Void
    @State private var trusted = Accessibility.isTrusted(prompt: false)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var core: [(Action, String)] {
        [
            (.focusRight, "Move focus to the next window. The strip slides to show it."),
            (.moveRight, "Move the focused window along the strip."),
            (.cycleWidth, "Step the window through your preset widths."),
            (.toggleFullWidth, "Fill the screen; press again to go back."),
            (.center, "Centre the window on screen."),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to MacSlider").font(.title).fontWeight(.semibold)
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
                                ? "Done. MacSlider can now arrange your windows."
                                : "macOS needs your permission before any app can move other apps’ windows. MacSlider asks for nothing else, works offline and collects no data."
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
                    Text("2. Learn five shortcuts").fontWeight(.medium)
                    ForEach(core, id: \.0) { action, explanation in
                        HStack(alignment: .firstTextBaseline) {
                            Text(store.settings.keymap.shortcuts(for: action).first?.displayString ?? "—")
                                .monospaced()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                                .frame(width: 90, alignment: .leading)
                            Text(explanation).font(.callout)
                        }
                    }
                    Text("Use H J K L or the arrow keys. Hold \(store.settings.keymap.dominantPrefix.symbols) and swipe two fingers on the trackpad to scroll the strip.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
#endif
