//
//  MapViewTransform.swift
//  Role: zoom and pan of the maps (design 2026-10-22): ONE transform shared by every map tile of a room, so the same part of the scan is in view on all of them. It is a view of the image panes'
//        `ZoomPan` measured in a tile of unit size, so the maps and the panes zoom by one rule: the zoom (1 = the whole scan fits the tile, never less) and, read through it, the point of the
//        picture, as fractions of its width and height, that sits at the tile's centre. Pinch and scroll zoom about the pointer, a drag or an ⌥-scroll pans, a double click resets. The
//        arithmetic is pure and held by a test. Each tile sits in the shared `ImageViewport` with its own `PaneZoomModel`, kept equal to this transform by `MapTileZoomSync`.
//

import CoreGraphics
import ShellControls
import SwiftUI

public nonisolated struct MapViewTransform: Equatable, Sendable {
    public static let maximumZoom: CGFloat = ZoomPan.maximumZoom
    /// The tile the state is measured in: one unit across and down, so its offsets are fractions of the tile and fit every tile size.
    public static let unitBox = CGSize(width: 1, height: 1)

    /// The zoom and the offset of the picture (in tile fractions, from the tile's centre), as the image panes keep them. Committed values only.
    public private(set) var zoomPan = ZoomPan()

    public init() {}

    /// The maps' view of a pane state in the unit box: never below the fit, never a gesture in flight, never off the picture.
    public init(_ state: ZoomPan) {
        var z = ZoomPan()
        if state.zoom > 1, state.zoom.isFinite {
            z.zoom = min(state.zoom, Self.maximumZoom)
            z.offset = ZoomPan.clampedOffset(state.offset, zoom: z.zoom, in: Self.unitBox)
        }
        zoomPan = z
    }

    /// 1 shows the whole picture; 2 shows half of its width and height.
    public var zoom: CGFloat { zoomPan.zoom }
    /// The picture's point (0...1 across and down) at the centre of the tile.
    public var center: CGPoint {
        CGPoint(x: 0.5 - zoomPan.offset.width / zoom, y: 0.5 - zoomPan.offset.height / zoom)
    }

    public var isFit: Bool { zoom <= 1 }

    public mutating func reset() { self = MapViewTransform() }

    /// Zoom by `factor`, keeping the picture point `anchor` (0...1, the point under the pointer) where it is on the tile.
    public mutating func zoom(by factor: CGFloat, about anchor: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        let target = min(max(zoom * factor, 1), Self.maximumZoom)
        guard target != zoom else { return }
        // The anchor as the panes measure it: unit-box points from the tile's centre.
        let center = center
        let screen = CGPoint(x: (anchor.x - center.x) * zoom, y: (anchor.y - center.y) * zoom)
        var next = zoomPan
        next.step(by: target / zoom, in: Self.unitBox, anchor: screen)
        next.zoom = target   // exactly the clamped target, not zoom * (target / zoom)
        next.offset = ZoomPan.clampedOffset(next.offset, zoom: target, in: Self.unitBox)
        zoomPan = next
    }

    /// Move the view by a drag of `translation` points over a tile of `size` points: the picture follows the pointer.
    public mutating func pan(by translation: CGSize, in size: CGSize) {
        guard size.width > 0, size.height > 0, zoom > 1 else { return }
        let proposed = CGSize(width: zoomPan.offset.width + translation.width / size.width,
                              height: zoomPan.offset.height + translation.height / size.height)
        zoomPan.offset = ZoomPan.clampedOffset(proposed, zoom: zoom, in: Self.unitBox)
    }

    /// The picture point (0...1) under a tile point of a tile `size` points across.
    public func picturePoint(forTile point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return center }
        return CGPoint(x: center.x + (point.x / size.width - 0.5) / zoom, y: center.y + (point.y / size.height - 0.5) / zoom)
    }

    /// Where the picture is drawn: the scale about the tile's centre and the offset in points that put `center` at the centre.
    public func placement(in size: CGSize) -> (scale: CGFloat, offset: CGSize) {
        (zoom, CGSize(width: zoomPan.offset.width * size.width, height: zoomPan.offset.height * size.height))
    }

    /// The point of the zoomed content (the picture's own, unscaled points) that sits under a tile point: the inverse of `placement`. Gestures read their locations in the tile's own space, which does not
    /// move with the content, and map them through this.
    public func contentPoint(forTile point: CGPoint, in size: CGSize) -> CGPoint {
        let p = placement(in: size)
        return CGPoint(x: size.width / 2 + (point.x - size.width / 2 - p.offset.width) / p.scale, y: size.height / 2 + (point.y - size.height / 2 - p.offset.height) / p.scale)
    }
}

nonisolated extension MapViewTransform {
    /// The pane state of a tile `size` points across that draws this transform: the same zoom, the offset in the tile's points (what
    /// the tile's `ImageViewport` and `zoomPanPlacement` take).
    public func paneState(in size: CGSize) -> ZoomPan {
        var state = ZoomPan()
        state.zoom = zoom
        state.offset = CGSize(width: zoomPan.offset.width * size.width, height: zoomPan.offset.height * size.height)
        return state
    }

    /// The transform a tile's pane state means, a gesture in flight included (its effective zoom and offset), never below the fit.
    public init(pane state: ZoomPan, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { self.init(); return }
        var unit = ZoomPan()
        unit.zoom = state.effectiveZoom
        unit.offset = CGSize(width: state.effectiveOffset.width / size.width, height: state.effectiveOffset.height / size.height)
        self.init(unit)
    }
}

/// How one tile's pane zoom and the room's one shared transform are kept equal. Pure, so a test holds the two rules that matter: a
/// gesture in flight on a tile is shared live and never written back onto that tile, and nothing stays below the fit.
nonisolated enum MapTileZoomSync {
    static func inFlight(_ state: ZoomPan) -> Bool { state.liveZoom != 1 || state.liveOffset != .zero }

    /// Equal but for rounding: a transform read back through a tile's points (times the size, then divided by it) may differ in the
    /// last bit, and tiles of two sizes must not hand such a difference back and forth.
    static func same(_ a: ZoomPan, _ b: ZoomPan, tolerance: CGFloat) -> Bool {
        abs(a.zoom - b.zoom) <= 1e-9 && abs(a.offset.width - b.offset.width) <= tolerance && abs(a.offset.height - b.offset.height) <= tolerance
            && a.liveZoom == b.liveZoom && a.liveOffset == b.liveOffset
    }

    /// The tile's pane changed (a gesture, the wheel, VoiceOver): the shared transform to write (nil: unchanged) and, once no gesture
    /// is in flight, the pane state to put back on the tile (nil: it is already the transform; set when it went below the fit).
    static func fromPane(_ state: ZoomPan, shared: MapViewTransform, size: CGSize) -> (shared: MapViewTransform?, pane: ZoomPan?) {
        let meant = MapViewTransform(pane: state, in: size)
        var back: ZoomPan?
        if !inFlight(state) {
            let normal = meant.paneState(in: size)
            if !same(normal, state, tolerance: 1e-6) { back = normal }
        }
        return (same(meant.zoomPan, shared.zoomPan, tolerance: 1e-9) ? nil : meant, back)
    }

    /// The shared transform changed (another tile, the View menu, a double click, a drag on the regions layer): the state to put on
    /// this tile's pane, nil when it already shows it or a gesture is in flight on it (it is the source).
    static func fromShared(_ shared: MapViewTransform, pane: ZoomPan, size: CGSize) -> ZoomPan? {
        guard !inFlight(pane) else { return nil }
        let state = shared.paneState(in: size)
        return same(state, pane, tolerance: 1e-6) ? nil : state
    }
}

/// The View menu's Zoom commands over the maps: a `PaneZoomModel` whose box is the unit tile, kept equal to the room's `MapViewTransform`. The menu
/// zooms about the tiles' centre (the pointer is in the menu bar, or over one of several tiles), by the panes' step, and Zoom to Fit is the double click.
@MainActor
final class MapZoomCommandBridge {
    let model = PaneZoomModel()

    init() { model.box = MapViewTransform.unitBox }

    /// The room's transform changed (a wheel, a pinch, a drag, a double click): the menu's model follows.
    func follow(_ transform: MapViewTransform) {
        if model.state != transform.zoomPan { model.state = transform.zoomPan }
    }

    /// The menu changed the model: the transform it means (the maps never zoom below the fit), and the model put back on it.
    func transform() -> MapViewTransform {
        let t = MapViewTransform(model.state)
        follow(t)
        return t
    }
}

/// Keeps the bridge and the room's transform equal. Its own view, so a zoom tick re-evaluates this modifier and not the maps block around it.
private struct MapZoomCommandsModifier: ViewModifier {
    @Binding var transform: MapViewTransform
    @State private var bridge = MapZoomCommandBridge()

    func body(content: Content) -> some View {
        content
            .zoomCommandTarget(bridge.model, isTarget: true)
            .onChange(of: transform, initial: true) { _, new in bridge.follow(new) }
            .onChange(of: bridge.model.state) { _, _ in
                let next = bridge.transform()
                if next != transform { transform = next }
            }
    }
}

extension View {
    /// Publishes the maps' shared `transform` to View > Zoom In, Zoom Out and Zoom to Fit (about the tiles' centre; Zoom to Fit is the
    /// double click). Apply it once, to the block that holds a room's tiles.
    public func mapZoomCommandTarget(_ transform: Binding<MapViewTransform>) -> some View {
        modifier(MapZoomCommandsModifier(transform: transform))
    }
}
