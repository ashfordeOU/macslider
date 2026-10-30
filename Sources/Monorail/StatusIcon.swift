#if os(macOS)
import AppKit

/// The menu bar glyph, matching the app icon: an M of three windows with the
/// middle one slid down (hollow while paused). Drawn as a template image so macOS
/// tints it for light and dark menu bars.
enum StatusIcon {
    static func image(paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.set()
            // The M: two outlined windows standing tall…
            let sides = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 4.5, height: 13), xRadius: 1.6, yRadius: 1.6)
            sides.append(NSBezierPath(roundedRect: NSRect(x: 12, y: 1.5, width: 4.5, height: 13), xRadius: 1.6, yRadius: 1.6))
            sides.lineWidth = 1.2
            sides.stroke()
            // …and the middle one, slid down.
            let middle = NSRect(x: 7, y: 2, width: 4, height: 8.5)
            if paused {
                let outline = NSBezierPath(roundedRect: middle.insetBy(dx: 0.6, dy: 0.6), xRadius: 1.4, yRadius: 1.4)
                outline.lineWidth = 1.2
                outline.stroke()
            } else {
                NSBezierPath(roundedRect: middle, xRadius: 1.4, yRadius: 1.4).fill()
            }
            // Where it slid from.
            NSBezierPath(roundedRect: NSRect(x: 8.4, y: 12, width: 1.2, height: 2.5), xRadius: 0.6, yRadius: 0.6).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = paused ? "Monorail (paused)" : "Monorail"
        return image
    }
}
#endif
