#if os(macOS)
import AppKit
import CoreLocation
import CoreWLAN
import MonorailCore
import SwiftUI

/// Runs auto rules: switch profile or apply a saved layout at a time of day,
/// or when the Mac joins a Wi-Fi network.
final class AutoRules: NSObject, CLLocationManagerDelegate {
    var rules: [AutoRule] = [] {
        didSet { if rules.contains(where: { $0.trigger == .wifi && $0.isEnabled }) { askForWiFiAccess() } }
    }
    var fire: (AutoRule) -> Void = { _ in }

    private var timer: Timer?
    private var lastMinute = -1
    private var lastNetwork: String?
    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
    }

    func start() {
        timer?.invalidate()
        lastNetwork = Self.currentNetwork()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.check() }
    }

    /// The Wi-Fi network's name. macOS only tells apps it after Location
    /// access is allowed.
    static func currentNetwork() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    var hasWiFiAccess: Bool {
        let status = location.authorizationStatus
        return status == .authorizedAlways || status == .authorized
    }

    private func askForWiFiAccess() {
        guard location.authorizationStatus == .notDetermined else { return }
        location.requestWhenInUseAuthorization()
    }

    private func check() {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if minute != lastMinute {
            lastMinute = minute
            let weekday = calendar.component(.weekday, from: now)
            for rule in rules where rule.isDue(minuteOfDay: minute, weekday: weekday) { fire(rule) }
        }
        let network = Self.currentNetwork()
        if network != lastNetwork {
            lastNetwork = network
            if let network {
                for rule in rules where rule.trigger == .wifi && rule.isEnabled
                    && rule.network.caseInsensitiveCompare(network) == .orderedSame
                {
                    fire(rule)
                }
            }
        }
    }
}

/// A small floating live picture of one window, kept in a screen corner.
/// Click it to go to the window; drag it anywhere; close it from its corner.
final class PictureInPicture {
    var focus: (WindowID) -> Void = { _ in }
    var onNeedsPermission: () -> Void = {}

    private var panels: [WindowID: (panel: NSPanel, model: PiPModel, timer: Timer)] = [:]

    func toggle(_ id: WindowID, title: String) {
        if let entry = panels.removeValue(forKey: id) {
            entry.timer.invalidate()
            entry.panel.orderOut(nil)
            return
        }
        guard WindowThumbnails.isAllowed else {
            onNeedsPermission()
            return
        }
        let model = PiPModel(title: title)
        let size = CGSize(width: 340, height: 220)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(panels.count) * 24
        let panel = NSPanel(
            contentRect: NSRect(
                x: screen.maxX - size.width - 20 - offset, y: screen.minY + 20 + offset, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 180, height: 120)
        panel.contentView = NSHostingView(rootView: PiPView(
            model: model,
            open: { [weak self] in self?.focus(id) },
            close: { [weak self] in self?.toggle(id, title: title) }))
        panel.orderFrontRegardless()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak model] _ in
            WindowThumbnails.capture([id]) { images in
                guard let model else { return }
                if let image = images[id] {
                    model.image = image
                    model.misses = 0
                } else {
                    model.misses += 1
                    // The window closed: put the picture away.
                    if model.misses > 4 { self?.toggle(id, title: title) }
                }
            }
        }
        timer.fire()
        panels[id] = (panel, model, timer)
    }
}

final class PiPModel: ObservableObject {
    @Published var image: NSImage?
    var misses = 0
    let title: String

    init(title: String) {
        self.title = title
    }
}

private struct PiPView: View {
    @ObservedObject var model: PiPModel
    let open: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = model.image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.85))
            .onTapGesture(perform: open)
            if hovering {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Close picture in picture")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.15)))
        .onHover { hovering = $0 }
        .help(model.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Picture in picture: \(model.title)")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
