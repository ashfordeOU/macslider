#if os(macOS)
import AppKit

/// Hot edges: rest the pointer against the left or right edge of a display
/// and the strip slides that way, one window at a time while it stays there.
/// Off by default; only outer display edges count (inner ones lead to the
/// next display).
final class HotEdges {
    /// true for the right edge.
    var onSlide: (Bool) -> Void = { _ in }

    private var monitor: Any?
    private var timer: Timer?
    private var edge: Bool?
    private static let dwell = 0.35
    private static let repeatInterval = 0.7

    func setEnabled(_ enabled: Bool) {
        if enabled, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in self?.pointerMoved() }
        } else if !enabled, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            cancel()
        }
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        guard NSEvent.pressedMouseButtons == 0,
            let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
        else { return cancel() }
        let visible = screen.visibleFrame
        // Ignore the menu bar and Dock areas.
        guard point.y > visible.minY + 4, point.y < visible.maxY - 4 else { return cancel() }
        let atLeft = point.x <= screen.frame.minX + 1 && !hasNeighbour(of: screen, onRight: false)
        let atRight = point.x >= screen.frame.maxX - 2 && !hasNeighbour(of: screen, onRight: true)
        guard atLeft || atRight else { return cancel() }
        let right = atRight
        guard edge != right else { return }
        cancel()
        edge = right
        timer = Timer.scheduledTimer(withTimeInterval: Self.dwell, repeats: false) { [weak self] _ in
            guard let self, self.edge == right else { return }
            self.onSlide(right)
            self.timer = Timer.scheduledTimer(withTimeInterval: Self.repeatInterval, repeats: true) { [weak self] _ in
                guard let self, self.edge == right else { return }
                self.onSlide(right)
            }
        }
    }

    private func hasNeighbour(of screen: NSScreen, onRight: Bool) -> Bool {
        NSScreen.screens.contains { other in
            other != screen && (onRight ? abs(other.frame.minX - screen.frame.maxX) < 2 : abs(other.frame.maxX - screen.frame.minX) < 2)
        }
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
        edge = nil
    }
}
#endif
