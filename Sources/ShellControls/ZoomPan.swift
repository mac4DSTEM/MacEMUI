// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/UI/ZoomPan.swift (macTEM@51c944c macTEM/UI/ZoomPan.swift folded in: nothing to fold; macTEM's copy is this file minus the badge, `FocusedValues.paneZoom` and `zoomCommandTarget`, all kept here, and a shorter `PaneZoomModel` comment, mac4DSTEM's kept)
// Changes: made public with explicit inits where an app builds one; `ZoomPan` marked `nonisolated` (pure value type); `PanDirection` nonisolated.
// END MOVED FROM
import SwiftUI

/// Zoom and pan for a scientific image pane — pure SwiftUI.
///
/// UI deliberately drops the AppKit scroll-wheel monitor the old panes
/// installed (`NSEvent.addLocalMonitorForEvents`, application-wide, which
/// swallowed scrolls for the whole app whenever a pane's hover never
/// reported `.ended`). What is left:
/// - `MagnifyGesture`: a trackpad pinch. It zooms ABOUT THE POINTER, the point the pinch began at, so the pixel you are looking
///   at stays under it.
/// - View > Zoom In, Zoom Out, Zoom to Fit (`ZoomCommands`), with the shortcuts, for the keyboard and a mouse: about the pointer
///   when it is over the pane, else about the pane's centre.
/// - VoiceOver's zoom and pan actions, and a double-click, which fits the image to the pane again.
///
/// **A mouse wheel does not zoom through `zoomPan`.** An earlier version of this comment said macOS synthesises magnification from the wheel with
/// a modifier. Nothing documents that: Apple describes `MagnifyGesture` as tracking a magnification event sequence, and a search of
/// the SwiftUI documentation (2026-10-14) finds no scroll-wheel hook either. The claim is withdrawn rather than relied on, and
/// the menu is the mouse's route; `zoomPanWheel` is the opt-in wheel, through `onScrollWheel` (bounded to the pane). Only the old monitor bought a wheel route, at the cost of the global event trap above. (The
/// same sentence is in `SpectrumStripView`'s header comment.)
///
/// The clamp is the science-relevant part. The views scale the image about
/// its centre (`scaleEffect(drawZoom)`) and then offset it in screen points
/// (`offset(effectiveOffset)`), so the scaled image is `size * zoom` wide and
/// one edge reaches the pane's edge exactly when `|offset| = size * (zoom - 1) / 2`
/// per axis. The clamp stops there, so panning can never push the image out
/// of its own pane.
public nonisolated struct ZoomPan: Equatable, Sendable {
    public var zoom: CGFloat = 1
    public var offset: CGSize = .zero

    /// In-flight gesture accumulators, committed on `.onEnded`.
    public var liveZoom: CGFloat = 1
    public var liveOffset: CGSize = .zero

    public init() {}

    public static let minimumZoom: CGFloat = 0.25
    public static let maximumZoom: CGFloat = 64

    public var effectiveZoom: CGFloat { zoom * liveZoom }
    public var effectiveOffset: CGSize {
        CGSize(width: offset.width + liveOffset.width,
               height: offset.height + liveOffset.height)
    }

    /// The zoom actually handed to a `scaleEffect`, floored so a pane can
    /// never collapse to nothing.
    public var drawZoom: CGFloat { max(Self.minimumZoom, effectiveZoom) }

    public mutating func reset() { self = ZoomPan() }

    public static func clampZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumZoom, max(minimumZoom, zoom))
    }

    /// One step of the VoiceOver / keyboard-free zoom actions: a factor of 2
    /// per step, through the same clamp as a pinch (`clampZoom`, then the pan
    /// is pulled back inside the pane as `.onEnded` does).
    public static let accessibilityStepFactor: CGFloat = 2

    /// The pane's spoken hint: one brief outcome phrase (the gestures are for the pointer; VoiceOver has the actions).
    public static let accessibilityHint = "Zoom with the Zoom in and Zoom out actions."

    /// Zoom by `factor` about `anchor`, the point to keep still, in screen points from the box's centre (`.zero`: the centre).
    public mutating func step(by factor: CGFloat, in box: CGSize, anchor: CGPoint = .zero) {
        let target = Self.clampZoom(zoom * factor)
        offset = Self.clampedOffset(
            Self.anchoredOffset(offset, from: zoom, to: target, anchor: anchor), zoom: target, in: box)
        zoom = target
    }

    // MARK: Zoom about a point

    /// The views scale the image about the box's centre `c` and then offset it in screen points, so a point `p` of the image
    /// (box points) lands at `c + zoom * (p - c) + offset`. Keeping the image point under `anchor` (screen points from `c`)
    /// where it is, while the zoom goes from `from` to `to`, gives the offset below. Zooming in from a valid state never leaves
    /// the clamp (the overhang grows by exactly the amount the anchor can ask for); zooming out can, and the caller clamps.
    public static func anchoredOffset(_ offset: CGSize, from: CGFloat, to: CGFloat, anchor: CGPoint) -> CGSize {
        guard from > 0 else { return offset }
        let ratio = to / from
        return CGSize(width: anchor.x - ratio * (anchor.x - offset.width),
                      height: anchor.y - ratio * (anchor.y - offset.height))
    }

    /// A point of the box, as a screen-point offset from the box's centre (what `anchor` takes).
    public static func anchor(for point: CGPoint, in box: CGSize) -> CGPoint {
        CGPoint(x: point.x - box.width / 2, y: point.y - box.height / 2)
    }

    /// One scroll event of the wheel or a two-finger scroll: a zoom about the pointer by `ScrollZoom.factor`, through the same clamp
    /// as a pinch. `location` is the pointer in the box's points from its top-leading corner. Continuous: every event of a gesture
    /// steps, so a trackpad's small deltas zoom smoothly and a wheel click steps by about 10 %.
    public mutating func wheel(delta: CGFloat, isPrecise: Bool, at location: CGPoint, in box: CGSize) {
        step(by: ScrollZoom.factor(delta: delta, isPrecise: isPrecise), in: box, anchor: Self.anchor(for: location, in: box))
    }

    /// A pinch in flight: the live zoom and the live offset that keep `anchor` still. The zoom is clamped as the commit will
    /// clamp it, so the picture never shows a zoom the gesture will not keep.
    public mutating func pinch(magnification: CGFloat, anchor: CGPoint, in box: CGSize) {
        let target = Self.clampZoom(zoom * magnification)
        let live = zoom > 0 ? target / zoom : 1
        let moved = Self.clampedOffset(
            Self.anchoredOffset(offset, from: zoom, to: target, anchor: anchor), zoom: target, in: box)
        let shift = CGSize(width: moved.width - offset.width, height: moved.height - offset.height)
        // Skip a write that changes nothing: each one re-evaluates the pane.
        if liveZoom != live { liveZoom = live }
        if liveOffset != shift { liveOffset = shift }
    }

    /// A pinch's end: commit what `pinch` showed.
    public mutating func endPinch(magnification: CGFloat, anchor: CGPoint, in box: CGSize) {
        liveZoom = 1
        liveOffset = .zero
        step(by: magnification, in: box, anchor: anchor)
    }

    // MARK: Badge

    /// The zoom as the reader's locale writes it, three significant digits ("2", "2.5", "0.5"); nil at 1× (nothing to say).
    public static func badgeNumber(zoom: CGFloat, locale: Locale = .autoupdatingCurrent) -> String? {
        guard abs(zoom - 1) > 0.005 else { return nil }
        return Double(zoom).formatted(.number.locale(locale).grouping(.never).precision(.significantDigits(1...3)))
    }

    /// The pane's zoom badge: "×2.5".
    public static func badgeText(zoom: CGFloat, locale: Locale = .autoupdatingCurrent) -> String? {
        badgeNumber(zoom: zoom, locale: locale).map { "\u{00D7}" + $0 }
    }

    /// The badge as VoiceOver and the tooltip say it.
    public static func badgeSpoken(zoom: CGFloat, locale: Locale = .autoupdatingCurrent) -> String? {
        badgeNumber(zoom: zoom, locale: locale).map { "Zoomed to \($0) times" }
    }

    /// The VoiceOver pan actions: the view moves over the image in the named direction (so the image content moves the other
    /// way, as in the spectrum strip's "Pan left"). One step is a fifth of the pane.
    public nonisolated enum PanDirection: CaseIterable, Sendable { case left, right, up, down }
    public static let accessibilityPanFraction: CGFloat = 1.0 / 5.0

    /// Through the same clamp as a drag: never past the image's edge, and a no-op at zoom 1 (nothing to pan).
    public mutating func pan(_ direction: PanDirection, in box: CGSize) {
        let dx = box.width * Self.accessibilityPanFraction, dy = box.height * Self.accessibilityPanFraction
        var proposed = offset
        switch direction {
        case .left: proposed.width += dx
        case .right: proposed.width -= dx
        case .up: proposed.height += dy
        case .down: proposed.height -= dy
        }
        offset = Self.clampedOffset(proposed, zoom: zoom, in: box)
    }

    /// Pure, so the rule itself is unit-testable without a view.
    public static func clampedOffset(
        _ proposed: CGSize, zoom: CGFloat, in size: CGSize
    ) -> CGSize {
        guard zoom > 1, size.width > 0, size.height > 0 else { return .zero }
        // The offset is applied after scaleEffect, in screen points, so the
        // limit is the scaled overhang per side: size * (zoom - 1) / 2.
        let fraction = (zoom - 1) / 2
        let maxX = size.width * fraction
        let maxY = size.height * fraction
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }
}

/// One pane's zoom, as a reference so more than the pane can reach it: the View menu's commands act on the pane that publishes
/// it as the focused scene value (`FocusedValues.paneZoom`), and a class compares by identity there (a closure or a struct of
/// closures would not). The pane owns it as `@State`; nothing else holds state about the zoom.
///
/// `box` (the drawn image's size, which the pan clamp is measured against) and `pointer` (where the pointer is over the pane, in
/// box points from its top-leading corner, nil outside) are kept current by the pane and are not observed: nothing draws them.
@MainActor
@Observable
public final class PaneZoomModel {
    public var state = ZoomPan()
    @ObservationIgnored public var box: CGSize = .zero
    @ObservationIgnored public var pointer: CGPoint?

    public init() {}

    /// The zoom commands' step: the VoiceOver step (a factor of 2), about the pointer when it is over the pane (the keyboard
    /// shortcut), else about the centre (the menu was chosen with the mouse, so the pointer is in the menu bar).
    public func zoomIn() { step(ZoomPan.accessibilityStepFactor) }
    public func zoomOut() { step(1 / ZoomPan.accessibilityStepFactor) }

    /// Back to 1×, the image fitted to the pane (what a double-click does).
    public func fit() { update { $0.reset() } }

    private func step(_ factor: CGFloat) {
        let anchor = pointer.map { ZoomPan.anchor(for: $0, in: box) } ?? .zero
        update { $0.step(by: factor, in: box, anchor: anchor) }
    }

    /// The one way the zoom changes: on a copy, assigned back. The `@Observable` setter compares an Equatable value and does not
    /// notify when nothing changed (a gesture reports the same clamped value at every tick of an edge, and each notification
    /// re-evaluates the pane); an in-place mutation (`change(&state)`, the `_modify` accessor) always notifies.
    public func update(_ change: (inout ZoomPan) -> Void) {
        var next = state
        change(&next)
        state = next
    }
}

extension FocusedValues {
    /// The zoom of the pane View > Zoom acts on; nil when no pane offers one (no dataset, or a room without an image pane).
    @Entry public var paneZoom: PaneZoomModel?
}

private struct ZoomPanModifier: ViewModifier {
    let model: PaneZoomModel
    /// The drawn image's box — the clamp is expressed against the pixels,
    /// not against whatever the container happens to be.
    let box: CGSize
    /// The pointer over the pane, in this view's own box points, for a pane that reads a value under it (the comparison panels).
    /// One hover handler serves both, so the pane needs no second `onContinuousHover` on the same view.
    var onHover: ((HoverPhase) -> Void)?

    func body(content: Content) -> some View {
        content
            .gesture(
                SimultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            // About the point the pinch began at, so the pixel under the pointer stays under it.
                            model.update {
                                $0.pinch(magnification: value.magnification,
                                         anchor: ZoomPan.anchor(for: value.startLocation, in: box), in: box)
                            }
                        }
                        .onEnded { value in
                            // Zooming out while panned pulls the image back inside the pane (`step` clamps).
                            model.update {
                                $0.endPinch(magnification: value.magnification,
                                            anchor: ZoomPan.anchor(for: value.startLocation, in: box), in: box)
                            }
                        },
                    DragGesture()
                        .onChanged { value in
                            let state = model.state
                            let proposed = CGSize(
                                width: state.offset.width + value.translation.width,
                                height: state.offset.height + value.translation.height
                            )
                            // Live clamp, so the drag stops at the edge
                            // rather than rubber-banding past it.
                            let allowed = ZoomPan.clampedOffset(
                                proposed, zoom: state.effectiveZoom, in: box
                            )
                            let live = CGSize(
                                width: allowed.width - state.offset.width,
                                height: allowed.height - state.offset.height
                            )
                            // Pinned at an edge the drag keeps reporting the
                            // same clamped value; do not re-publish it.
                            if state.liveOffset != live { model.update { $0.liveOffset = live } }
                        }
                        .onEnded { value in
                            let state = model.state
                            let proposed = CGSize(
                                width: state.offset.width + value.translation.width,
                                height: state.offset.height + value.translation.height
                            )
                            let committed = ZoomPan.clampedOffset(proposed, zoom: state.zoom, in: box)
                            model.update { $0.offset = committed; $0.liveOffset = .zero }
                        }
                )
            )
            .onTapGesture(count: 2) {
                resetZoom(model: model, reduceMotion: reduceMotion)
            }
            // Where the zoom commands anchor: the pointer over the pane, in this view's own (unzoomed) box points.
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): model.pointer = location
                case .ended: model.pointer = nil
                }
                onHover?(phase)
            }
            .onChange(of: box, initial: true) { model.box = box }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

/// Reset, animated only when the reader has not asked for Reduce Motion.
@MainActor
private func resetZoom(model: PaneZoomModel, reduceMotion: Bool) {
    if reduceMotion {
        model.fit()
    } else {
        withAnimation(.snappy) { model.fit() }
    }
}

/// The zoom gestures' accessible twins: pinch, drag-to-pan-only and
/// double-click gave VoiceOver and Switch Control users no way to zoom or to
/// reset. Applied to the pane's accessibility container, where the actions are
/// listed (review 2026-10-07, F5). Nothing is drawn.
private struct ZoomPanAccessibilityActions: ViewModifier {
    let model: PaneZoomModel
    let box: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Zoom in") {
                model.update { $0.step(by: ZoomPan.accessibilityStepFactor, in: box) }
            }
            .accessibilityAction(named: "Zoom out") {
                model.update { $0.step(by: 1 / ZoomPan.accessibilityStepFactor, in: box) }
            }
            .accessibilityAction(named: "Pan left") { model.update { $0.pan(.left, in: box) } }
            .accessibilityAction(named: "Pan right") { model.update { $0.pan(.right, in: box) } }
            .accessibilityAction(named: "Pan up") { model.update { $0.pan(.up, in: box) } }
            .accessibilityAction(named: "Pan down") { model.update { $0.pan(.down, in: box) } }
            .accessibilityAction(named: "Reset zoom") {
                resetZoom(model: model, reduceMotion: reduceMotion)
            }
    }
}

private struct ZoomPanWheelModifier: ViewModifier {
    let model: PaneZoomModel
    let box: CGSize

    func body(content: Content) -> some View {
        // The one AppKit route (`onScrollWheel`, a bounded local monitor; never the old application-wide one).
        content.onScrollWheel { event in
            guard event.delta != 0 else { return }
            model.update { $0.wheel(delta: event.delta, isPrecise: event.isPrecise, at: event.location, in: box) }
        }
    }
}

extension View {
    /// The wheel and a two-finger scroll zoom about the pointer, as a pinch does. Apply it to the same view as `zoomPan`, with
    /// the same `box`. Separate from `zoomPan` so a pane that already routes the wheel (or that wants it for scrolling) opts in.
    public func zoomPanWheel(_ model: PaneZoomModel, box: CGSize) -> some View {
        modifier(ZoomPanWheelModifier(model: model, box: box))
    }

    /// "Zoom in", "Zoom out", "Pan left/right/up/down" and "Reset zoom" as accessibility actions, for the
    /// same `model` and `box` the pane's `.zoomPan` uses.
    public func zoomPanAccessibilityActions(_ model: PaneZoomModel, box: CGSize) -> some View {
        modifier(ZoomPanAccessibilityActions(model: model, box: box))
    }

    /// Pinch to zoom about the pointer, drag to pan, double-click to fit. `box` is the drawn image's size, which is what the pan
    /// clamp is measured against.
    public func zoomPan(_ model: PaneZoomModel, box: CGSize, onHover: ((HoverPhase) -> Void)? = nil) -> some View {
        modifier(ZoomPanModifier(model: model, box: box, onHover: onHover))
    }

    /// Publishes this pane's zoom to the View menu while `isTarget`; nothing otherwise.
    public func zoomCommandTarget(_ model: PaneZoomModel, isTarget: Bool) -> some View {
        focusedSceneValue(\.paneZoom, isTarget ? model : nil)
    }
}
