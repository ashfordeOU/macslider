#if os(macOS)
import AppKit
import MonorailCore

/// Moves and resizes windows off the main thread.
///
/// Each app gets its own serial queue, so a slow app (one busy enough to
/// take its time answering Accessibility calls) only delays its own windows
/// and never freezes Monorail. Requests are coalesced: if a window gets a new
/// target before the last one was applied, only the newest is sent, so a slow
/// app skips animation frames instead of falling behind.
final class WindowWriter {
    private struct Request {
        var element: AXUIElement
        var frame: CGRect
        var sizeChanged: Bool
    }

    /// Called on the main thread once a window has actually been moved.
    var didApply: (WindowID) -> Void = { _ in }

    private var queues: [pid_t: DispatchQueue] = [:]
    private var pending: [WindowID: Request] = [:]
    private let lock = NSLock()

    func set(_ frame: CGRect, of id: WindowID, element: AXUIElement, pid: pid_t, sizeChanged: Bool) {
        lock.lock()
        let queued = pending[id] != nil
        // Keep a size change from an earlier, superseded request.
        let resize = sizeChanged || (pending[id]?.sizeChanged ?? false)
        pending[id] = Request(element: element, frame: frame, sizeChanged: resize)
        lock.unlock()
        guard !queued else { return }
        queue(for: pid).async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let request = self.pending.removeValue(forKey: id)
            self.lock.unlock()
            guard let request else { return }
            AXUIElementSetMessagingTimeout(request.element, 1.0)
            request.element.setFrame(request.frame, sizeChanged: request.sizeChanged)
            DispatchQueue.main.async { self.didApply(id) }
        }
    }

    /// Drops queued work for an app that quit.
    func forget(pid: pid_t) {
        queues[pid] = nil
    }

    private func queue(for pid: pid_t) -> DispatchQueue {
        if let queue = queues[pid] { return queue }
        let queue = DispatchQueue(label: "org.ashforde.monorail.writer.\(pid)", qos: .userInteractive)
        queues[pid] = queue
        return queue
    }
}
#endif
