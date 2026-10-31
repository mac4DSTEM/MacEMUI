import SwiftUI

/// The one image viewport a room's picture sits in, so zoom and pan behave the same in every room: a pinch and the wheel zoom
/// about the pointer, a drag pans, ⌥-scroll pans, a double click fits, VoiceOver has its zoom and pan actions, and View > Zoom acts
/// on it. Every route is `ZoomPan`'s arithmetic through the pane's `PaneZoomModel`, measured against one `box`.
///
/// The container does not draw the picture: it hands its content the pane's live zoom (`ZoomPan`), because the rooms draw in two
/// ways. A Metal view keeps a pane-sized drawable and takes the zoom through its shader (`MetalDisplayTransform` with `drawZoom` and
/// `effectiveOffset`), and so do the marks drawn over it; a plain picture (a `CGImage`, a SwiftUI drawing) is placed with
/// `zoomPanPlacement(_:)`, the same map.
///
/// ```swift
/// ImageViewport(zoomModel, box: box, onHover: { hovered($0) }) { zoom in
///     Image(decorative: picture, scale: 1).resizable().zoomPanPlacement(zoom)
/// }
/// ```
///
/// Two layouts:
/// - `pane` nil (an image pane): the content is laid out at `box`, clipped to it, and takes the gestures itself, so a tool's own gestures
///   inside the content (a measuring overlay, a click on the FFT) come first.
/// - `pane` set (a letterboxed picture, `box` smaller than the pane and centred in it): the content is laid out at `pane` and clipped
///   there, so a zoomed picture fills the letterbox; the gestures, the clamp, the anchors and the hover are a `box`-sized layer centred
///   over it.
///
/// `wheel`, `accessibilityActions` and whether `pane` is set are fixed for a pane's life: each picks a different structure, and changing it would give the
/// content a new identity (a Metal view rebuilt, a gesture in flight lost).
///
/// What sits outside the container stays the pane's: its footer and scale bar, a border, a context menu, its accessibility element.
public struct ImageViewport<Content: View>: View {
    private let model: PaneZoomModel
    private let box: CGSize
    private let pane: CGSize?
    private let wheel: Bool
    private let accessibilityActions: Bool
    private let isCommandTarget: Bool
    private let onHover: ((HoverPhase) -> Void)?
    private let content: (ZoomPan) -> Content

    /// - `model`: the pane's zoom, owned by the pane as `@State` (it is also what View > Zoom acts on).
    /// - `box`: the drawn picture's size, which the pan clamp, the anchors and the hover are measured against.
    /// - `pane`: the size the content is laid out and clipped at, when larger than `box` (a letterbox); nil: `box`.
    /// - `wheel`: the wheel and a two-finger scroll zoom (⌥: pan); false for a pane that keeps the wheel for itself.
    /// - `accessibilityActions`: VoiceOver's zoom and pan actions on the container; false when the pane puts them
    ///   (`zoomPanAccessibilityActions`) on its own labelled accessibility element, so they are listed once, where the label is.
    /// - `isCommandTarget`: whether View > Zoom acts on this pane (one pane of a room publishes, the one last clicked or the only one).
    /// - `onHover`: the pointer over the picture, in `box` points, for a pane that reads the value under it.
    /// - `content`: the picture, given the live zoom (a pinch or drag in flight included).
    public init(_ model: PaneZoomModel, box: CGSize, pane: CGSize? = nil, wheel: Bool = true, accessibilityActions: Bool = true,
                isCommandTarget: Bool = true, onHover: ((HoverPhase) -> Void)? = nil, @ViewBuilder content: @escaping (ZoomPan) -> Content) {
        self.model = model; self.box = box; self.pane = pane; self.wheel = wheel; self.accessibilityActions = accessibilityActions
        self.isCommandTarget = isCommandTarget; self.onHover = onHover; self.content = content
    }

    public var body: some View {
        if let pane {
            content(model.state)
                .frame(width: pane.width, height: pane.height)
                .clipped()
                .overlay {
                    Color.clear.frame(width: box.width, height: box.height).contentShape(Rectangle())
                        .modifier(ZoomRoutes(model: model, box: box, wheel: wheel, onHover: onHover))
                }
                .modifier(ZoomPaneScope(model: model, box: box, accessibilityActions: accessibilityActions, isCommandTarget: isCommandTarget))
        } else {
            content(model.state)
                .frame(width: box.width, height: box.height)
                .clipped()
                .contentShape(Rectangle())
                .modifier(ZoomRoutes(model: model, box: box, wheel: wheel, onHover: onHover))
                .modifier(ZoomPaneScope(model: model, box: box, accessibilityActions: accessibilityActions, isCommandTarget: isCommandTarget))
        }
    }
}

/// The pointer's routes, on the `box`-sized view that takes them: pinch, drag and double click with the hover, and the wheel when the pane takes it.
private struct ZoomRoutes: ViewModifier {
    let model: PaneZoomModel
    let box: CGSize
    let wheel: Bool
    let onHover: ((HoverPhase) -> Void)?

    func body(content: Content) -> some View {
        // No scroll catcher at all without the wheel: it consumes every scroll over the view, which a pane keeping the wheel needs.
        if wheel {
            content.zoomPan(model, box: box, onHover: onHover).zoomPanWheel(model, box: box)
        } else {
            content.zoomPan(model, box: box, onHover: onHover)
        }
    }
}

/// The routes that are not the pointer's: VoiceOver's actions and View > Zoom, on the whole container.
private struct ZoomPaneScope: ViewModifier {
    let model: PaneZoomModel
    let box: CGSize
    let accessibilityActions: Bool
    let isCommandTarget: Bool

    func body(content: Content) -> some View {
        if accessibilityActions {
            content.zoomPanAccessibilityActions(model, box: box).zoomCommandTarget(model, isTarget: isCommandTarget)
        } else {
            content.zoomCommandTarget(model, isTarget: isCommandTarget)
        }
    }
}

extension View {
    /// A plain picture placed by the pane's zoom, as the Metal view's shader places its pixels: scaled about the box's centre by the
    /// drawn zoom, then moved by the offset in screen points (the offset is applied after the scale, so it is not scaled).
    public func zoomPanPlacement(_ state: ZoomPan) -> some View {
        scaleEffect(state.drawZoom)
            .offset(state.effectiveOffset)
    }
}
