//
//  ScrollWheel.swift
//  Role: a scroll wheel or two-finger scroll over a view, for zoom (the maps and the spectrum: Velox and GMS zoom with the wheel). SwiftUI has no scroll hook on macOS, so this is the one AppKit piece: a
//        transparent NSView behind the content that gets the scrollWheel events of the pointer over it, and ONLY those: no application-wide event monitor (the older panes' monitor swallowed scrolls for the whole app,
//        see `ZoomPan`). Where SwiftUI cannot do the job, named here as the rules ask.
//

import AppKit
import SwiftUI

/// What one scroll event says: the vertical delta (positive scrolls the content up, as the wheel's own sign), whether it came from a trackpad (precise, many small events) and where the pointer was, in the view's
/// coordinates with the origin at the top left.
public struct ScrollWheelEvent: Sendable {
    public var delta: CGFloat
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

        override var isFlipped: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            guard let handler else { super.scrollWheel(with: event); return }
            handler(ScrollWheelEvent(delta: event.scrollingDeltaY, isPrecise: event.hasPreciseScrollingDeltas,
                                     location: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags))
        }
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
