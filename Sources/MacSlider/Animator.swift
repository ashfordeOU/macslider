#if os(macOS)
import AppKit
import MacSliderCore

/// Moves windows to their targets over a short ease-out animation.
///
/// Only positions are animated: a window's size is set once, up front,
/// because resizing another app's window every frame makes it re-layout
/// its content and looks worse than an instant resize.
final class Animator {
    struct Track {
        var from: Rect
        var to: Rect
    }

    /// Applies a frame to a window. `sizeChanged` is false for intermediate frames.
    var apply: (WindowID, Rect, _ sizeChanged: Bool) -> Void = { _, _, _ in }
    /// Called once all tracks have reached their targets.
    var onFinish: () -> Void = {}

    private var tracks: [WindowID: Track] = [:]
    private var current: [WindowID: Rect] = [:]
    private var start: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0.2
    private var timer: Timer?

    var isRunning: Bool { timer != nil }

    /// Animates from each window's current (or last known) frame to its target.
    /// Calling this mid-animation retargets smoothly from where windows are now.
    func animate(_ targets: [WindowID: (from: Rect, to: Rect)], duration: CFTimeInterval) {
        var next: [WindowID: Track] = [:]
        for (id, target) in targets {
            let from = current[id] ?? target.from
            if from.isClose(to: target.to, tolerance: 0.5) { continue }
            let sizeChanged = !sameSize(from, target.to)
            // Resize immediately at the starting position; then slide.
            var start = from
            if sizeChanged {
                start.width = target.to.width
                start.height = target.to.height
                apply(id, start, true)
            }
            next[id] = Track(from: start, to: target.to)
        }
        // Windows that were animating but are no longer targeted finish where they were headed.
        for (id, track) in tracks where next[id] == nil && targets[id] == nil {
            apply(id, track.to, false)
        }
        tracks = next
        current = [:]
        guard !tracks.isEmpty else {
            stop()
            onFinish()
            return
        }
        self.duration = max(duration, 0.01)
        start = CACurrentMediaTime()
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.step() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        step()
    }

    /// Jumps every running animation to its end.
    func finishNow() {
        guard isRunning else { return }
        for (id, track) in tracks { apply(id, track.to, false) }
        tracks = [:]
        current = [:]
        stop()
        onFinish()
    }

    func cancel() {
        tracks = [:]
        current = [:]
        stop()
    }

    private func step() {
        let elapsed = CACurrentMediaTime() - start
        let progress = min(elapsed / duration, 1)
        let eased = 1 - pow(1 - progress, 3)  // ease-out cubic
        for (id, track) in tracks {
            var frame = track.from.interpolated(to: track.to, t: eased).rounded()
            frame.width = track.to.width
            frame.height = track.to.height
            if current[id] != frame {
                apply(id, frame, false)
                current[id] = frame
            }
        }
        if progress >= 1 {
            tracks = [:]
            current = [:]
            stop()
            onFinish()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sameSize(_ a: Rect, _ b: Rect) -> Bool {
        abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }
}
#endif
