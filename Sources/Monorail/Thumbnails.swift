#if os(macOS)
import AppKit
import MonorailCore
import ScreenCaptureKit
import SwiftUI

/// Live images of windows, for the overview and the slider-bar previews.
/// Needs Screen Recording permission; without it the UI shows app icons.
/// Uses ScreenCaptureKit on macOS 14 and later, and the older Core Graphics
/// call on macOS 13.
enum WindowThumbnails {
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Set once the user has asked for previews in this run of Monorail.
    /// macOS only applies a new Screen Recording permission after a relaunch.
    private(set) static var requested = false

    static var needsRelaunch: Bool { requested && !isAllowed }

    static func requestAccess() {
        requested = true
        // Shows the system prompt the first time; after that, macOS only
        // allows changing it in System Settings.
        if !CGRequestScreenCaptureAccess(),
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Captures `ids` and calls `completion` on the main thread.
    static func capture(_ ids: [WindowID], completion: @escaping ([WindowID: NSImage]) -> Void) {
        guard isAllowed, !ids.isEmpty else { return }
        if #available(macOS 14.0, *) {
            Task {
                let images = ImageBox(await ModernCapture.capture(ids))
                await MainActor.run { completion(images.value) }
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                var images: [WindowID: NSImage] = [:]
                for id in ids { images[id] = LegacyCapture.capture(id) }
                DispatchQueue.main.async { completion(images) }
            }
        }
    }

    /// Quits and reopens Monorail, so a new Screen Recording permission applies.
    static func relaunch() {
        let script = #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; /usr/bin/open "$2""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c", script, "monorail-relaunch",
            String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
        ]
        guard (try? process.run()) != nil else { return }
        NSApp.terminate(nil)
    }
}

/// Hands captured images from the capture task to the main thread. The images
/// are created once and never mutated, so sharing them is safe.
private final class ImageBox: @unchecked Sendable {
    let value: [WindowID: NSImage]
    init(_ value: [WindowID: NSImage]) { self.value = value }
}

@available(macOS 14.0, *)
private enum ModernCapture {
    /// The window list is reused briefly; previews refresh several times a second.
    private static var cached: (content: SCShareableContent, time: Date)?

    private static func content() async -> SCShareableContent? {
        if let cached, Date().timeIntervalSince(cached.time) < 1.5 { return cached.content }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return nil }
        cached = (content, Date())
        return content
    }

    /// Captures all windows at once rather than one after another.
    static func capture(_ ids: [WindowID]) async -> [WindowID: NSImage] {
        guard let content = await content() else { return [:] }
        let targets = ids.compactMap { id in content.windows.first { $0.windowID == id } }
        return await withTaskGroup(of: (WindowID, CGImage?).self) { group in
            for window in targets {
                group.addTask { (window.windowID, await capture(window)) }
            }
            var images: [WindowID: NSImage] = [:]
            for await (id, image) in group {
                if let image { images[id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
            }
            return images
        }
    }

    private static func capture(_ window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Thumbnail size: sharp at preview scale without capturing full resolution.
        let scale = min(1, 640 / max(window.frame.width, 1)) * 2
        config.width = max(Int(window.frame.width * scale), 2)
        config.height = max(Int(window.frame.height * scale), 2)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

private enum LegacyCapture {
    private typealias CreateImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    // Looked up at runtime: the call is deprecated in newer SDKs.
    private static let createImage: CreateImageFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
            let symbol = dlsym(handle, "CGWindowListCreateImage")
        else { return nil }
        return unsafeBitCast(symbol, to: CreateImageFn.self)
    }()

    static func capture(_ id: WindowID) -> NSImage? {
        guard let createImage else { return nil }
        let includingWindow: UInt32 = 1 << 3
        let boundsIgnoreFramingAndNominal: UInt32 = (1 << 0) | (1 << 4)
        guard let image = createImage(.null, includingWindow, id, boundsIgnoreFramingAndNominal)?.takeRetainedValue(),
            image.width > 1, image.height > 1
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

/// "Show live previews", which becomes "Relaunch to turn on previews" once
/// the user has allowed Screen Recording (macOS needs the restart).
struct LivePreviewsButton: View {
    enum Style { case bordered, link }

    var style: Style = .bordered
    var onChange: () -> Void
    @State private var needsRelaunch = WindowThumbnails.needsRelaunch
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if needsRelaunch {
                button("Relaunch to turn on previews", symbol: "arrow.clockwise") { WindowThumbnails.relaunch() }
                    .help("macOS applies Screen Recording permission after Monorail restarts. Your windows stay put.")
            } else {
                button("Show live previews…", symbol: "eye") {
                    WindowThumbnails.requestAccess()
                    needsRelaunch = WindowThumbnails.needsRelaunch
                    onChange()
                }
                .help("Needs Screen Recording permission. Previews stay on your Mac and are never saved.")
            }
        }
        .onReceive(poll) { _ in needsRelaunch = WindowThumbnails.needsRelaunch }
    }

    @ViewBuilder
    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        switch style {
        case .bordered:
            Button(action: action) { Label(title, systemImage: symbol) }
        case .link:
            Button(title, action: action).buttonStyle(.link).font(.system(size: 11))
        }
    }
}
#endif
