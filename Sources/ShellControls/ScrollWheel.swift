//
//  ScrollWheel.swift
//  Role: a scroll wheel or two-finger scroll over a view, for zoom (the maps and the spectrum: Velox and GMS zoom with the wheel). SwiftUI has no scroll hook on macOS, so this is the one AppKit piece: a
//        transparent NSView behind the content with ONE local event monitor. SwiftUI content above the view (an Image with gestures) wins the hit test, so the view's own scrollWheel never fires; the monitor sees
//        the event first. It is bounded: it consumes only a scroll whose window is this view's window and whose pointer is inside this view's bounds (and the view is visible), so it can never swallow the app's
//        scrolls as the old application-wide monitor in `ZoomPan`'s history did. Where SwiftUI cannot do the job, named here as the rules ask.
//

import AppKit
import SwiftUI

/// What one scroll event says: the vertical delta (positive scrolls the content up, as the wheel's own sign), whether it came from a trackpad (precise, many small events) and where the pointer was, in the view's
/// coordinates with the origin at the top left.
public struct ScrollWheelEvent: Sendable {
    public var delta: CGFloat
    /// The horizontal delta, same sign convention (an ⌥-scroll pans with both).
    public var deltaX: CGFloat = 0
    public var isPrecise: Bool
    public var location: CGPoint
    public var modifiers: NSEvent.ModifierFlags
}

private struct ScrollWheelBackground: NSViewRepresentable {
    let handler: (ScrollWheelEvent) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.handler = handler }

    final class CatcherView: NSView {
        var handler: ((ScrollWheelEvent) -> Void)?
        nonisolated(unsafe) private var monitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.consume(event) ?? event
            }
        }

        private func consume(_ event: NSEvent) -> NSEvent? {
            guard let handler, event.window === window, !isHiddenOrHasHiddenAncestor else { return event }
            let point = convert(event.locationInWindow, from: nil)
            guard ScrollWheelRouting.accepts(point: point, in: bounds) else { return event }
            handler(ScrollWheelEvent(delta: event.scrollingDeltaY, deltaX: event.scrollingDeltaX, isPrecise: event.hasPreciseScrollingDeltas, location: point, modifiers: event.modifierFlags))
            return nil
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// Whether a scroll at `point` (in the view's coordinates) belongs to a view with `bounds`; the edge counts as inside.
public nonisolated enum ScrollWheelRouting {
    public static func accepts(point: CGPoint, in bounds: CGRect) -> Bool {
        point.x >= bounds.minX && point.x <= bounds.maxX && point.y >= bounds.minY && point.y <= bounds.maxY
    }
}

extension View {
    /// Calls `perform` for the scroll events of the pointer over this view (not over a view above it that takes them itself).
    public func onScrollWheel(perform handler: @escaping (ScrollWheelEvent) -> Void) -> some View {
        background(ScrollWheelBackground(handler: handler))
    }
}

/// The zoom factor a scroll event asks for: a trackpad's small deltas (points) scale smoothly, a wheel's click (lines) steps by about 10 %. Scrolling up zooms in.
public nonisolated enum ScrollZoom {
    public static func factor(delta: CGFloat, isPrecise: Bool) -> CGFloat {
        guard delta.isFinite else { return 1 }
        return exp((isPrecise ? 0.01 : 0.1) * delta)
    }
}
