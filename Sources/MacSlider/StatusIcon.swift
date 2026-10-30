#if os(macOS)
import AppKit

/// The menu bar glyph, matching the app icon: three windows on a strip, the
/// focused one filled, above a slider. Drawn as a template image so macOS
/// tints it for light and dark menu bars.
enum StatusIcon {
    static func image(paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.set()
            // Neighbouring windows, cut off at the edges.
            let side = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 5.5, width: 4, height: 8), xRadius: 1.2, yRadius: 1.2)
            side.append(NSBezierPath(roundedRect: NSRect(x: 15.5, y: 5.5, width: 4, height: 8), xRadius: 1.2, yRadius: 1.2))
            side.lineWidth = 1
            side.stroke()

            // The focused window.
            let main = NSRect(x: 6, y: 4.5, width: 8, height: 10)
            if paused {
                let outline = NSBezierPath(roundedRect: main.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.6, yRadius: 1.6)
                outline.lineWidth = 1
                outline.stroke()
                NSBezierPath(rect: NSRect(x: 8.3, y: 7, width: 1.3, height: 5)).fill()
                NSBezierPath(rect: NSRect(x: 10.4, y: 7, width: 1.3, height: 5)).fill()
            } else {
                NSBezierPath(roundedRect: main, xRadius: 1.6, yRadius: 1.6).fill()
            }

            // The slider: a track with a knob under the focused window.
            NSBezierPath(roundedRect: NSRect(x: 2, y: 1, width: 16, height: 1), xRadius: 0.5, yRadius: 0.5).fill()
            NSBezierPath(roundedRect: NSRect(x: 7.5, y: 0, width: 5, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = paused ? "MacSlider (paused)" : "MacSlider"
        return image
    }
}
#endif
