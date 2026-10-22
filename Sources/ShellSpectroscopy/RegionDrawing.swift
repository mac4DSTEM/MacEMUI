//
//  RegionDrawing.swift
//  Role: the drawing tools of a map tile (design 2026-10-22 §2.1): drag a rectangle or an ellipse, click a polygon's vertices (the first closes it), drag a line.
//        The layer sits over the tile's picture, draws the regions with `RegionOverlay` and the shape being drawn, and hands back what was drawn in
//        scan pixels; the room keeps the regions and pools their spectra. The geometry helpers are pure so a test holds them.
//

import SwiftUI

/// The shape the next gesture on a map draws.
public nonisolated enum RegionTool: String, CaseIterable, Identifiable, Sendable {
    case pointer, rectangle, ellipse, polygon, line

    public var id: String { rawValue }
    public var title: String { self == .pointer ? "Select" : rawValue.capitalized }
    public var symbolName: String {
        switch self {
        case .pointer: "cursorarrow"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .polygon: "pentagon"
        case .line: "line.diagonal"
        }
    }
    public var hint: String {
        switch self {
        case .pointer: "Click a region to select it, drag to move the view; ⌫ deletes the selected region. Pick a shape to draw."
        case .rectangle: "Drag a rectangle on any map to sum its pixels."
        case .ellipse: "Drag to draw the ellipse inscribed in a rectangle."
        case .polygon: "Click the vertices on any map; click the first vertex to close the polygon."
        case .line: "Drag a line on any map: the Profile tab plots each map along it."
        }
    }
}

/// The geometry of the drawing, in points of the picture and pixels of the scan.
public nonisolated enum RegionDrawing {
    /// The scan pixel under `point` of a picture `size` points across, or nil outside it.
    public static func pixel(at point: CGPoint, in size: CGSize, scanWidth: Int, scanHeight: Int) -> (x: Int, y: Int)? {
        guard size.width > 0, size.height > 0, scanWidth > 0, scanHeight > 0,
              point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }
        return (min(Int(point.x / size.width * Double(scanWidth)), scanWidth - 1), min(Int(point.y / size.height * Double(scanHeight)), scanHeight - 1))
    }

    /// A position in the picture as a continuous scan coordinate (pixel i covers [i, i+1)), clamped to the picture.
    public static func scanPoint(_ point: CGPoint, in size: CGSize, scanWidth: Int, scanHeight: Int) -> RegionPoint {
        let x = min(max(point.x, 0), size.width), y = min(max(point.y, 0), size.height)
        return RegionPoint(x: Double(x / max(size.width, 1)) * Double(scanWidth), y: Double(y / max(size.height, 1)) * Double(scanHeight))
    }

    /// The pixels spanned by two corners, inclusive of both (the pixel under each corner is in), clamped to the grid; nil for corners off the picture.
    public static func spannedBox(from a: CGPoint, to b: CGPoint, in size: CGSize, scanWidth: Int, scanHeight: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        let ca = CGPoint(x: min(max(a.x, 0), size.width), y: min(max(a.y, 0), size.height))
        let cb = CGPoint(x: min(max(b.x, 0), size.width), y: min(max(b.y, 0), size.height))
        guard let p = pixel(at: ca, in: size, scanWidth: scanWidth, scanHeight: scanHeight),
              let q = pixel(at: cb, in: size, scanWidth: scanWidth, scanHeight: scanHeight) else { return nil }
        return (min(p.x, q.x), min(p.y, q.y), max(p.x, q.x) + 1, max(p.y, q.y) + 1)
    }

    /// Whether a click at `point` closes a polygon that has `vertices` (three or more), by landing within `radius` points of its first vertex.
    public static func closesPolygon(_ vertices: [RegionPoint], click point: CGPoint, in size: CGSize, scanWidth: Int, scanHeight: Int, radius: CGFloat) -> Bool {
        guard vertices.count >= 3, let first = vertices.first, scanWidth > 0, scanHeight > 0 else { return false }
        let sx = size.width / CGFloat(scanWidth), sy = size.height / CGFloat(scanHeight)
        return hypot(first.x * sx - point.x, first.y * sy - point.y) <= radius
    }
}

/// What the pointer is doing to a region while it is dragged: a new shape being drawn (`id` nil) or the selected region being moved or resized, with the geometry so far.
public struct RegionDragUpdate: Equatable, Sendable {
    public var id: UUID?
    public var geometry: RegionGeometry
    public init(id: UUID?, geometry: RegionGeometry) { self.id = id; self.geometry = geometry }
}

/// The layer over a tile's picture. It is as large as the picture; `scanWidth` x `scanHeight` pixels map to its frame.
public struct RegionDrawingLayer: View {
    private let tool: RegionTool
    private let set: SpectralRegionSet
    private let scanWidth: Int
    private let scanHeight: Int
    private let pointer: (x: Int, y: Int)?
    private let onRectangle: (Int, Int, Int, Int) -> Void
    private let onEllipse: (Int, Int, Int, Int) -> Void
    private let onPolygon: ([RegionPoint]) -> Void
    private let onLine: (RegionPoint, RegionPoint) -> Void
    private let onHover: ((x: Int, y: Int)?) -> Void
    private let onEdit: (UUID, RegionGeometry) -> Void
    private let onDrag: (RegionDragUpdate?) -> Void
    private let view: MapViewTransform
    private let tileSpace: String
    private let onPan: (CGSize) -> Void
    private let onSelect: (UUID?) -> Void

    @State private var lastPan: CGSize = .zero
    @State private var dragging: CGRect?
    /// A handle or the body of the selected region being dragged: the region, where it started, what the press landed on and the geometry shown meanwhile.
    @State private var editing: (id: UUID, original: RegionGeometry, hit: RegionHit, shown: RegionGeometry)?
    @State private var draggingLine: (CGPoint, CGPoint)?
    @State private var vertices: [RegionPoint] = []

    private static let vertexSize: CGFloat = 7
    private static let firstVertexSize: CGFloat = 11
    private static let closeRadius: CGFloat = 9
    private static let handleSize: CGFloat = 7
    private static let handleRadius: CGFloat = 8

    /// The set with the region being edited at its dragged geometry.
    private var shownSet: SpectralRegionSet {
        guard let editing else { return set }
        var copy = set
        copy.setGeometry(editing.id, editing.shown)
        return copy
    }

    private var shownSelected: SpectralRegion? {
        guard let selected = shownSet.selected, selected.isVisible else { return nil }
        return selected
    }

    public init(tool: RegionTool, set: SpectralRegionSet, scanWidth: Int, scanHeight: Int, pointer: (x: Int, y: Int)? = nil,
                onRectangle: @escaping (Int, Int, Int, Int) -> Void, onEllipse: @escaping (Int, Int, Int, Int) -> Void,
                onPolygon: @escaping ([RegionPoint]) -> Void, onLine: @escaping (RegionPoint, RegionPoint) -> Void,
                onHover: @escaping ((x: Int, y: Int)?) -> Void, onEdit: @escaping (UUID, RegionGeometry) -> Void = { _, _ in },
                onDrag: @escaping (RegionDragUpdate?) -> Void = { _ in }, view: MapViewTransform = MapViewTransform(), tileSpace: String = "mapTile", onPan: @escaping (CGSize) -> Void = { _ in },
                onSelect: @escaping (UUID?) -> Void = { _ in }) {
        self.tool = tool; self.set = set; self.scanWidth = scanWidth; self.scanHeight = scanHeight; self.pointer = pointer
        self.onRectangle = onRectangle; self.onEllipse = onEllipse; self.onPolygon = onPolygon; self.onLine = onLine; self.onHover = onHover; self.onEdit = onEdit; self.onDrag = onDrag; self.view = view; self.tileSpace = tileSpace; self.onPan = onPan; self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let sx = size.width / CGFloat(max(scanWidth, 1)), sy = size.height / CGFloat(max(scanHeight, 1))
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(drag(size: size))
                    .gesture(tap(size: size), including: tool == .polygon || tool == .pointer ? .all : .none)
                RegionOverlay(set: shownSet, scanWidth: scanWidth, scanHeight: scanHeight, pixel: pointer, strokeScale: 1 / view.zoom)
                if let region = shownSelected {
                    ForEach(Array(RegionEditing.handles(of: region.geometry).enumerated()), id: \.offset) { _, h in
                        Rectangle().fill(.white).frame(width: Self.handleSize / view.zoom, height: Self.handleSize / view.zoom)
                            .overlay { Rectangle().stroke(.black.opacity(0.7), lineWidth: 1 / view.zoom) }
                            .position(x: h.point.x * sx, y: h.point.y * sy).allowsHitTesting(false)
                    }
                }
                if let dragging {
                    let shape = tool == .ellipse ? Path(ellipseIn: dragging) : Path(dragging)
                    shape.fill(.white.opacity(0.12)).allowsHitTesting(false)
                    shape.stroke(.white, lineWidth: 1.5).allowsHitTesting(false)
                }
                if let (a, b) = draggingLine {
                    Path { p in p.move(to: a); p.addLine(to: b) }.stroke(.white, lineWidth: 1.5).allowsHitTesting(false)
                }
                if !vertices.isEmpty {
                    Path { p in
                        p.move(to: CGPoint(x: vertices[0].x * sx, y: vertices[0].y * sy))
                        for v in vertices.dropFirst() { p.addLine(to: CGPoint(x: v.x * sx, y: v.y * sy)) }
                    }
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .allowsHitTesting(false)
                    ForEach(vertices.indices, id: \.self) { i in
                        Circle().stroke(.yellow, lineWidth: 1.5)
                            .frame(width: i == 0 ? Self.firstVertexSize : Self.vertexSize, height: i == 0 ? Self.firstVertexSize : Self.vertexSize)
                            .position(x: vertices[i].x * sx, y: vertices[i].y * sy).allowsHitTesting(false)
                    }
                }
            }
            .onContinuousHover(coordinateSpace: .named(tileSpace)) { phase in
                switch phase {
                case .active(let p): onHover(RegionDrawing.pixel(at: local(p, size), in: size, scanWidth: scanWidth, scanHeight: scanHeight))
                case .ended: onHover(nil)
                }
            }
            .onChange(of: tool) { vertices = [] }
        }
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(tileSpace))
            .onChanged { v0 in
                let v = Converted(start: local(v0.startLocation, size), location: local(v0.location, size), translation: v0.translation)
                let sx = size.width / CGFloat(max(scanWidth, 1)), sy = size.height / CGFloat(max(scanHeight, 1))
                if editing == nil, dragging == nil, draggingLine == nil, let selected = shownSelected,
                   let hit = RegionEditing.hit(selected.geometry, at: v.start, sx: sx, sy: sy, radius: Self.handleRadius / view.zoom) {
                    editing = (selected.id, selected.geometry, hit, selected.geometry)
                }
                if let current = editing {
                    let here = RegionDrawing.scanPoint(v.location, in: size, scanWidth: scanWidth, scanHeight: scanHeight)
                    let there = RegionDrawing.scanPoint(v.start, in: size, scanWidth: scanWidth, scanHeight: scanHeight)
                    switch current.hit {
                    case .body:
                        editing?.shown = RegionEditing.moved(current.original, dx: here.x - there.x, dy: here.y - there.y, scanWidth: scanWidth, scanHeight: scanHeight)
                    case .handle(let h):
                        editing?.shown = RegionEditing.resized(current.original, handle: h, to: here, scanWidth: scanWidth, scanHeight: scanHeight)
                    }
                    if let shown = editing?.shown { onDrag(RegionDragUpdate(id: current.id, geometry: shown)) }
                    return
                }
                if tool == .pointer {
                    // No handle or region body under the press: the drag moves the view.
                    onPan(CGSize(width: v.translation.width - lastPan.width, height: v.translation.height - lastPan.height))
                    lastPan = v.translation
                    return
                }
                if tool == .polygon { return }
                if tool == .line {
                    draggingLine = (clamp(v.start, size), clamp(v.location, size))
                    onDrag(RegionDragUpdate(id: nil, geometry: .line(RegionDrawing.scanPoint(v.start, in: size, scanWidth: scanWidth, scanHeight: scanHeight),
                                                                     RegionDrawing.scanPoint(v.location, in: size, scanWidth: scanWidth, scanHeight: scanHeight))))
                } else {
                    dragging = CGRect(x: min(v.start.x, v.location.x), y: min(v.start.y, v.location.y),
                                      width: abs(v.location.x - v.start.x), height: abs(v.location.y - v.start.y))
                    if let box = RegionDrawing.spannedBox(from: v.start, to: v.location, in: size, scanWidth: scanWidth, scanHeight: scanHeight) {
                        let g = RegionGeometry.rectangle(x0: Double(box.x0), y0: Double(box.y0), x1: Double(box.x1), y1: Double(box.y1))
                        if tool == .ellipse { onDrag(RegionDragUpdate(id: nil, geometry: .ellipse(x0: Double(box.x0), y0: Double(box.y0), x1: Double(box.x1), y1: Double(box.y1)))) }
                        else { onDrag(RegionDragUpdate(id: nil, geometry: g)) }
                    }
                }
            }
            .onEnded { v0 in
                let v = Converted(start: local(v0.startLocation, size), location: local(v0.location, size), translation: v0.translation)
                onDrag(nil)
                lastPan = .zero
                if let done = editing {
                    editing = nil
                    if done.shown != done.original { onEdit(done.id, done.shown) }
                    return
                }
                dragging = nil; draggingLine = nil
                if tool == .polygon || tool == .pointer { return }
                if tool == .line {
                    onLine(RegionDrawing.scanPoint(v.start, in: size, scanWidth: scanWidth, scanHeight: scanHeight),
                           RegionDrawing.scanPoint(v.location, in: size, scanWidth: scanWidth, scanHeight: scanHeight))
                } else if let box = RegionDrawing.spannedBox(from: v.start, to: v.location, in: size, scanWidth: scanWidth, scanHeight: scanHeight) {
                    tool == .ellipse ? onEllipse(box.x0, box.y0, box.x1, box.y1) : onRectangle(box.x0, box.y0, box.x1, box.y1)
                }
            }
    }

    /// The polygon tool: a click adds a vertex; a click on the first vertex (once there are three) closes the polygon.
    private func tap(size: CGSize) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .named(tileSpace)).onEnded { t0 in
            let t = (location: local(t0.location, size), 0)
            if tool == .pointer {
                let p = RegionDrawing.scanPoint(t.location, in: size, scanWidth: scanWidth, scanHeight: scanHeight)
                let tolerance = Double(Self.handleRadius / view.zoom / max(min(size.width / CGFloat(max(scanWidth, 1)), size.height / CGFloat(max(scanHeight, 1))), 0.001))
                onSelect(set.visible.last { RegionEditing.contains($0.geometry, p, tolerance: tolerance) }?.id)
                return
            }
            if RegionDrawing.closesPolygon(vertices, click: t.location, in: size, scanWidth: scanWidth, scanHeight: scanHeight, radius: Self.closeRadius) {
                onPolygon(vertices)
                vertices = []
                return
            }
            vertices.append(RegionDrawing.scanPoint(t.location, in: size, scanWidth: scanWidth, scanHeight: scanHeight))
        }
    }

    /// A location in the tile's own space (which does not move with the zoomed content), in the content's points.
    private func local(_ tilePoint: CGPoint, _ size: CGSize) -> CGPoint { view.contentPoint(forTile: tilePoint, in: size) }

    private struct Converted { var start: CGPoint; var location: CGPoint; var translation: CGSize }

    private func clamp(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height)) }
}
