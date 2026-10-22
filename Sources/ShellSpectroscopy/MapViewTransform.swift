//
//  MapViewTransform.swift
//  Role: zoom and pan of the maps (design 2026-10-22): ONE transform shared by every map tile of a room, so the same part of the scan is in view on all of them. It is a plain value: the zoom
//        (1 = the whole scan fits the tile) and the point of the picture, as fractions of its width and height, that sits at the tile's centre. Pinch and scroll zoom about the pointer, a drag pans,
//        a double click resets. The arithmetic is pure and held by a test.
//

import CoreGraphics

public nonisolated struct MapViewTransform: Equatable, Sendable {
    public static let maximumZoom: CGFloat = 64

    /// 1 shows the whole picture; 2 shows half of its width and height.
    public private(set) var zoom: CGFloat = 1
    /// The picture's point (0...1 across and down) at the centre of the tile.
    public private(set) var center = CGPoint(x: 0.5, y: 0.5)

    public init() {}

    public var isFit: Bool { zoom <= 1 }

    public mutating func reset() { self = MapViewTransform() }

    /// Zoom by `factor`, keeping the picture point `anchor` (0...1, the point under the pointer) where it is on the tile.
    public mutating func zoom(by factor: CGFloat, about anchor: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        let new = min(max(zoom * factor, 1), Self.maximumZoom)
        guard new != zoom else { return }
        // The anchor's offset from the centre, in tile fractions, is (anchor - center) * zoom; keeping it fixed gives the new centre.
        let fromCenter = CGPoint(x: (anchor.x - center.x) * zoom, y: (anchor.y - center.y) * zoom)
        center = CGPoint(x: anchor.x - fromCenter.x / new, y: anchor.y - fromCenter.y / new)
        zoom = new
        clamp()
    }

    /// Move the view by a drag of `translation` points over a tile of `size` points: the picture follows the pointer.
    public mutating func pan(by translation: CGSize, in size: CGSize) {
        guard size.width > 0, size.height > 0, zoom > 1 else { return }
        center = CGPoint(x: center.x - translation.width / (size.width * zoom), y: center.y - translation.height / (size.height * zoom))
        clamp()
    }

    /// The picture point (0...1) under a tile point of a tile `size` points across.
    public func picturePoint(forTile point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return center }
        return CGPoint(x: center.x + (point.x / size.width - 0.5) / zoom, y: center.y + (point.y / size.height - 0.5) / zoom)
    }

    /// Where the picture is drawn: the scale about the tile's centre and the offset in points that put `center` at the centre.
    public func placement(in size: CGSize) -> (scale: CGFloat, offset: CGSize) {
        (zoom, CGSize(width: (0.5 - center.x) * size.width * zoom, height: (0.5 - center.y) * size.height * zoom))
    }

    /// The point of the zoomed content (the picture's own, unscaled points) that sits under a tile point: the inverse of `placement`. Gestures read their locations in the tile's own space, which does not
    /// move with the content, and map them through this.
    public func contentPoint(forTile point: CGPoint, in size: CGSize) -> CGPoint {
        let p = placement(in: size)
        return CGPoint(x: size.width / 2 + (point.x - size.width / 2 - p.offset.width) / p.scale, y: size.height / 2 + (point.y - size.height / 2 - p.offset.height) / p.scale)
    }

    /// The view never leaves the picture: the centre stays half a view's span inside every edge.
    private mutating func clamp() {
        let half = 0.5 / zoom
        center = CGPoint(x: min(max(center.x, half), 1 - half), y: min(max(center.y, half), 1 - half))
    }
}
