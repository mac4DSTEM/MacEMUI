//
//  RegionEditing.swift
//  Role: moving and resizing a drawn region by handles (design 2026-10-22 §2.1): the selected region shows handles (eight on a rectangle or ellipse, a vertex
//        each on a polygon, the two ends of a line); a drag on a handle resizes, a drag inside moves. The geometry is pure so a test holds it; boxes snap to whole
//        pixels (the regions are pixel masks), polygon vertices and line ends stay continuous. `RegionDrawingLayer` calls it.
//

import CoreGraphics
import Foundation

/// A handle of the selected region: a box's corner or edge (`x`, `y` in -1, 0, 1: which side moves; 0 leaves that axis alone) or a vertex of a polygon or line.
public nonisolated enum RegionHandle: Equatable, Sendable {
    case box(x: Int, y: Int)
    case vertex(Int)
}

public nonisolated enum RegionHit: Equatable, Sendable {
    case handle(RegionHandle)
    case body
}

public nonisolated enum RegionEditing {
    /// The handles of a geometry with their scan positions.
    public static func handles(of geometry: RegionGeometry) -> [(handle: RegionHandle, point: RegionPoint)] {
        switch geometry {
        case .rectangle, .ellipse:
            let b = geometry.bounds
            let xs = [(-1, b.x0), (0, (b.x0 + b.x1) / 2), (1, b.x1)], ys = [(-1, b.y0), (0, (b.y0 + b.y1) / 2), (1, b.y1)]
            return xs.flatMap { x in ys.compactMap { y in (x.0 == 0 && y.0 == 0) ? nil : (RegionHandle.box(x: x.0, y: y.0), RegionPoint(x: x.1, y: y.1)) } }
        case .polygon(let v):
            return v.enumerated().map { (RegionHandle.vertex($0.offset), $0.element) }
        case .line(let a, let b):
            return [(.vertex(0), a), (.vertex(1), b)]
        }
    }

    /// What a press at `point` (points of a picture whose scan pixel is `sx` x `sy` points) lands on: a handle within `radius` points, else the body, else nothing.
    public static func hit(_ geometry: RegionGeometry, at point: CGPoint, sx: CGFloat, sy: CGFloat, radius: CGFloat) -> RegionHit? {
        var best: (RegionHandle, CGFloat)?
        for (handle, p) in handles(of: geometry) {
            let d = hypot(p.x * sx - point.x, p.y * sy - point.y)
            if d <= radius, d < (best?.1 ?? .infinity) { best = (handle, d) }
        }
        if let best { return .handle(best.0) }
        return contains(geometry, RegionPoint(x: Double(point.x / sx), y: Double(point.y / sy)), tolerance: Double(radius / max(min(sx, sy), 0.001))) ? .body : nil
    }

    /// Whether a scan position is on the region: inside a closed shape, within `tolerance` pixels of a line.
    public static func contains(_ geometry: RegionGeometry, _ p: RegionPoint, tolerance: Double) -> Bool {
        switch geometry {
        case .rectangle:
            let b = geometry.bounds
            return p.x >= b.x0 && p.x <= b.x1 && p.y >= b.y0 && p.y <= b.y1
        case .ellipse:
            let b = geometry.bounds
            let ax = (b.x1 - b.x0) / 2, ay = (b.y1 - b.y0) / 2
            guard ax > 0, ay > 0 else { return false }
            let dx = (p.x - (b.x0 + b.x1) / 2) / ax, dy = (p.y - (b.y0 + b.y1) / 2) / ay
            return dx * dx + dy * dy <= 1
        case .polygon(let v):
            guard v.count >= 3 else { return false }
            var inside = false
            var j = v.count - 1
            for i in 0..<v.count {
                let a = v[j], b = v[i]
                if (a.y > p.y) != (b.y > p.y), p.x < a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x) { inside.toggle() }
                j = i
            }
            return inside
        case .line(let a, let b):
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1) : 0
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)) <= tolerance
        }
    }

    /// The geometry moved by (`dx`, `dy`) scan pixels, kept inside the grid (it is shifted back rather than squeezed); boxes move in whole pixels.
    public static func moved(_ geometry: RegionGeometry, dx: Double, dy: Double, scanWidth: Int, scanHeight: Int) -> RegionGeometry {
        let b = geometry.bounds
        var (mx, my) = (dx, dy)
        if case .polygon = geometry {} else if case .line = geometry {} else { mx = mx.rounded(); my = my.rounded() }
        mx = min(max(mx, -b.x0), Double(scanWidth) - b.x1)
        my = min(max(my, -b.y0), Double(scanHeight) - b.y1)
        func shift(_ p: RegionPoint) -> RegionPoint { RegionPoint(x: p.x + mx, y: p.y + my) }
        switch geometry {
        case .rectangle(let x0, let y0, let x1, let y1): return .rectangle(x0: x0 + mx, y0: y0 + my, x1: x1 + mx, y1: y1 + my)
        case .ellipse(let x0, let y0, let x1, let y1): return .ellipse(x0: x0 + mx, y0: y0 + my, x1: x1 + mx, y1: y1 + my)
        case .polygon(let v): return .polygon(v.map(shift))
        case .line(let a, let c): return .line(shift(a), shift(c))
        }
    }

    /// The geometry with `handle` dragged to `point`. A box edge moves to the nearest whole pixel and never closes the box below one pixel; a vertex follows the
    /// point, kept inside the grid.
    public static func resized(_ geometry: RegionGeometry, handle: RegionHandle, to point: RegionPoint, scanWidth: Int, scanHeight: Int) -> RegionGeometry {
        let px = min(max(point.x, 0), Double(scanWidth)), py = min(max(point.y, 0), Double(scanHeight))
        switch (geometry, handle) {
        case (.rectangle, .box(let hx, let hy)), (.ellipse, .box(let hx, let hy)):
            var b = geometry.bounds
            if hx < 0 { b.x0 = min(px.rounded(), b.x1 - 1) } else if hx > 0 { b.x1 = max(px.rounded(), b.x0 + 1) }
            if hy < 0 { b.y0 = min(py.rounded(), b.y1 - 1) } else if hy > 0 { b.y1 = max(py.rounded(), b.y0 + 1) }
            if case .ellipse = geometry { return .ellipse(x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1) }
            return .rectangle(x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1)
        case (.polygon(var v), .vertex(let i)) where v.indices.contains(i):
            v[i] = RegionPoint(x: px, y: py)
            return .polygon(v)
        case (.line(let a, let c), .vertex(let i)):
            return i == 0 ? .line(RegionPoint(x: px, y: py), c) : .line(a, RegionPoint(x: px, y: py))
        default:
            return geometry
        }
    }
}
