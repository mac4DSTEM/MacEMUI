//
//  MapTileView.swift
//  Role: one map of a spectroscopy room as the corrected design draws it (2026-10-22): the picture at the size the grid gives it, its name in the corner, a calibrated scale bar that opens
//        the map's colour controls, ONE cursor (only the tile under the pointer marks the pixel), and, on the anchor
//        tile only, the regions and the tools that draw and edit them. Nothing is drawn over a picture but the cursor (no chip, no hover colour scale): the status line
//        carries the value, the histogram in the popover the scale. The picture itself (the pixels) and the numbers are the app's; this is the frame.
//        The picture sits in the shared `ImageViewport` (zoom and pan by the panes' routes), through a per-tile `PaneZoomModel` kept equal to the room's one
//        `MapViewTransform` (`MapTileZoomSync`). An app may draw its own marks over the picture in the overlay slot (mac4DSTEM: its precipitate glyphs).
//

import ShellControls
import ShellMetal
import SwiftUI

/// The regions and tools of the anchor tile: what is drawn over it and what drawing and editing hand back (scan pixels).
public struct MapTileRegions {
    public var set: SpectralRegionSet
    public var tool: RegionTool
    public var onRectangle: (Int, Int, Int, Int) -> Void
    public var onEllipse: (Int, Int, Int, Int) -> Void
    public var onPolygon: ([RegionPoint]) -> Void
    public var onLine: (RegionPoint, RegionPoint) -> Void
    public var onEdit: (UUID, RegionGeometry) -> Void
    public var onDrag: (RegionDragUpdate?) -> Void
    /// A click on a region selects it (nil: on none); the delete key removes the selected region.
    public var onSelect: (UUID?) -> Void
    public var onDelete: () -> Void

    public init(set: SpectralRegionSet, tool: RegionTool,
                onRectangle: @escaping (Int, Int, Int, Int) -> Void, onEllipse: @escaping (Int, Int, Int, Int) -> Void,
                onPolygon: @escaping ([RegionPoint]) -> Void, onLine: @escaping (RegionPoint, RegionPoint) -> Void,
                onEdit: @escaping (UUID, RegionGeometry) -> Void, onDrag: @escaping (RegionDragUpdate?) -> Void = { _ in },
                onSelect: @escaping (UUID?) -> Void = { _ in }, onDelete: @escaping () -> Void = {}) {
        self.set = set; self.tool = tool
        self.onRectangle = onRectangle; self.onEllipse = onEllipse; self.onPolygon = onPolygon; self.onLine = onLine; self.onEdit = onEdit; self.onDrag = onDrag
        self.onSelect = onSelect; self.onDelete = onDelete
    }
}

/// What the overlay slot of a tile is handed: it is laid out at `size` (the tile, in the picture's own unzoomed points) and zooms and
/// pans with the picture, so a mark at a scan pixel is placed by `size / scanWidth` and `size / scanHeight` alone. `zoom` is the live
/// zoom, for strokes and labels of a constant on-screen width (divide by it).
public struct MapTileOverlayContext: Equatable, Sendable {
    public var size: CGSize
    public var scanWidth: Int
    public var scanHeight: Int
    public var zoom: CGFloat

    public init(size: CGSize, scanWidth: Int, scanHeight: Int, zoom: CGFloat) {
        self.size = size; self.scanWidth = scanWidth; self.scanHeight = scanHeight; self.zoom = zoom
    }
}

public struct MapTileView<Controls: View, Overlay: View>: View {
    private let title: String
    private let detail: String?
    private let image: CGImage?
    private let size: CGSize
    private let scanWidth: Int
    private let scanHeight: Int
    private let pixelSize: Double?
    private let pixelUnit: String?
    private let filteredTag: Bool
    private let regions: MapTileRegions?
    private let inMix: Bool?
    private let onToggleMix: (() -> Void)?
    private let onHover: ((x: Int, y: Int)?) -> Void
    private let controls: Controls
    private let overlay: (MapTileOverlayContext) -> Overlay
    private let placeholder: String?
    @Binding private var transform: MapViewTransform
    /// This tile's pane zoom for its `ImageViewport`: the shared transform in this tile's points (`MapTileZoomSync`).
    @State private var zoomModel: PaneZoomModel
    @State private var local: MapPixel?
    @FocusState private var focused: Bool
    @State private var showControls = false

    /// - `pixelSize` / `pixelUnit`: the scan's real-space step ("nm") for the scale bar; nil draws the bar in scan pixels.
    /// - `inMix` / `onToggleMix`: on an element map, whether the map is in the colour mix (a ring on the tile) and the click that adds it or takes it out; nil on tiles that are not selectable.
    /// - `regions`: set on the anchor tile only. `filteredTag`: the picture is drawn through a display filter; a small tag beside the name says so.
    /// - `transform`: the room's one zoom and pan, shared by every tile.
    /// - `controls`: the content of the popover the scale bar opens (the map's colour, histogram and gamma).
    /// - `overlay`: the app's marks over the picture, under the regions; it zooms with the picture and takes no clicks (`MapTileOverlayContext`).
    public init(title: String, detail: String? = nil, image: CGImage?, size: CGSize, scanWidth: Int, scanHeight: Int,
                pixelSize: Double? = nil, pixelUnit: String? = nil, regions: MapTileRegions? = nil, filteredTag: Bool = false,
                inMix: Bool? = nil, onToggleMix: (() -> Void)? = nil, placeholder: String? = nil, transform: Binding<MapViewTransform> = .constant(MapViewTransform()),
                onHover: @escaping ((x: Int, y: Int)?) -> Void,
                @ViewBuilder controls: () -> Controls,
                @ViewBuilder overlay: @escaping (MapTileOverlayContext) -> Overlay) {
        self.placeholder = placeholder; self._transform = transform
        self.title = title; self.detail = detail; self.image = image; self.size = size; self.scanWidth = scanWidth; self.scanHeight = scanHeight
        self.pixelSize = pixelSize; self.pixelUnit = pixelUnit; self.filteredTag = filteredTag; self.regions = regions; self.inMix = inMix; self.onToggleMix = onToggleMix
        self.onHover = onHover; self.controls = controls(); self.overlay = overlay
        // The first state is the shared transform already, so the first frame draws it (the sync below keeps it so).
        let model = PaneZoomModel()
        model.state = transform.wrappedValue.paneState(in: size)
        self._zoomModel = State(initialValue: model)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            // The picture and what is drawn on it zoom and pan together in the shared viewport; the name and scale bar stay at the tile's corners.
            // The viewport publishes nothing to View > Zoom: the room publishes the shared transform once (`mapZoomCommandTarget`).
            ImageViewport(zoomModel, box: size, accessibilityActions: false, isCommandTarget: false, publishesCommands: false) { zoom in
                // What the tile draws: the live zoom never below the fit (a pinch out shows the fit, as every other tile does), the same
                // transform the regions map their points through.
                let view = MapViewTransform(pane: zoom, in: size)
                ZStack(alignment: .topLeading) {
                    if let image { Image(decorative: image, scale: 1).interpolation(.none).resizable() }
                    overlay(MapTileOverlayContext(size: size, scanWidth: scanWidth, scanHeight: scanHeight, zoom: view.zoom))
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .allowsHitTesting(false)
                    // The regions and their tools (anchor tile) or just the hover (every other tile). Only the tile under the pointer draws the cursor.
                    if let regions {
                        RegionDrawingLayer(tool: regions.tool, set: regions.set, scanWidth: scanWidth, scanHeight: scanHeight, pointer: local.map { (x: $0.x, y: $0.y) },
                                           onRectangle: regions.onRectangle, onEllipse: regions.onEllipse, onPolygon: regions.onPolygon, onLine: regions.onLine,
                                           onHover: { setPointer($0) }, onEdit: regions.onEdit, onDrag: regions.onDrag, view: view,
                                           onPan: { transform.pan(by: $0, in: size) }, onSelect: { focused = true; regions.onSelect($0) })
                    } else {
                        HoverReader(scanWidth: scanWidth, scanHeight: scanHeight) { setPointer($0) }
                        RegionOverlay(set: SpectralRegionSet(), scanWidth: scanWidth, scanHeight: scanHeight, pixel: local.map { (x: $0.x, y: $0.y) }, strokeScale: 1 / view.zoom)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                // The tile's clicks, inside the viewport so they come before its own double click: one gesture, the double click tried first, so it
                // never also fires the single click (the single click waits for the double-click interval, as in Finder and Preview).
                .gesture(TapGesture(count: 2).onEnded { perform(TileClickAction.effects(clickCount: 2, selectable: onToggleMix != nil)) }
                    .exclusively(before: TapGesture().onEnded { perform(TileClickAction.effects(clickCount: 1, selectable: onToggleMix != nil)) }))
                .zoomPanPlacement(view.paneState(in: size))
            }
            if image == nil, let placeholder {
                Text(placeholder).font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(16)
                    .frame(width: size.width, height: size.height).allowsHitTesting(false)
                    .accessibilityIdentifier("maps.placeholder")
            }
            HStack(spacing: 6) {
                Text("\(Text(title).fontWeight(.semibold))\(Text(detail.map { " · \($0)" } ?? "").foregroundStyle(.white.opacity(0.75)))")
                    .font(.caption).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .lineLimit(1)
                if filteredTag {
                    Text("filtered").font(.caption2).foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .accessibilityLabel("Display filter on")
                        .accessibilityIdentifier("maps.filteredTag")
                }
            }
            .padding(6)
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(.named("mapTile"))
        .clipped()
        .overlay(alignment: .bottomLeading) { scaleBar }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        // A hairline edge: a bright map would otherwise run into a light window.
        .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.separator) }
        // A map that is selected on the right wears a ring; a click on a map toggles it (what is shown in the colour mix).
        .overlay { if inMix == true { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 2).allowsHitTesting(false) } }
        // The one zoom of the room: this tile's pane and the shared transform kept equal both ways (a gesture in flight here is shared live,
        // never echoed back; nothing stays below the fit).
        .onChange(of: zoomModel.state) { _, state in
            let sync = MapTileZoomSync.fromPane(state, shared: transform, size: size)
            if let shared = sync.shared { transform = shared }
            if let pane = sync.pane { zoomModel.state = pane }
        }
        .onChange(of: transform) { _, shared in
            if let pane = MapTileZoomSync.fromShared(shared, pane: zoomModel.state, size: size) { zoomModel.state = pane }
        }
        .onChange(of: size) { _, newSize in
            if let pane = MapTileZoomSync.fromShared(transform, pane: zoomModel.state, size: newSize) { zoomModel.state = pane }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onDeleteCommand { regions?.onDelete() }
        .help(onToggleMix == nil ? "" : (inMix == true ? "Shown in the colour mix: click to take it out" : "Click to show this map in the colour mix"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
        // VoiceOver's zoom and pan actions, the viewport's, listed once, on the labelled tile.
        .zoomPanAccessibilityActions(zoomModel, box: size)
    }

    private var accessibilityName: String {
        guard let detail else { return "\(title) map" }
        return "\(title) map, \(detail)"
    }

    private func perform(_ effects: Set<TileClickAction>) {
        if effects.contains(.focus) { focused = true }
        if effects.contains(.toggleMix) { onToggleMix?() }
        if effects.contains(.resetView) { transform.reset() }
    }

    /// The pointer moves many times within one pixel: the state and the app are told only when the pixel changes.
    private func setPointer(_ pixel: (x: Int, y: Int)?) {
        let new = pixel.map { MapPixel(x: $0.x, y: $0.y) }
        guard new != local else { return }
        local = new
        onHover(pixel)
    }

    private var scaleBar: some View {
        let perPoint = (pixelSize ?? 1) * Double(scanWidth) / max(Double(size.width), 1) / Double(transform.zoom)
        return ScaleBar(unitsPerPoint: perPoint, unitLabel: pixelUnit ?? "px")
            .padding(4)
            .contentShape(Rectangle())
            .onTapGesture { showControls.toggle() }
            .help("Colour, range and gamma of this map")
            .popover(isPresented: $showControls, arrowEdge: .top) { controls.padding(12).frame(width: 260) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the colour controls of this map")
            .accessibilityIdentifier("maps.scaleBar.\(title)")
    }
}

/// What a click on a map tile does, by its click count. Pure, so a test holds that a double click only resets the view.
nonisolated enum TileClickAction: Hashable, Sendable {
    case focus, toggleMix, resetView

    /// A single click focuses the tile and, on a selectable map, toggles it in the colour mix; a double click focuses it and returns
    /// to the whole scan, and nothing else.
    static func effects(clickCount: Int, selectable: Bool) -> Set<TileClickAction> {
        switch clickCount {
        case ..<1: []
        case 1: selectable ? [.focus, .toggleMix] : [.focus]
        default: [.focus, .resetView]
        }
    }
}

/// A scan pixel; Equatable so a state holding it is not rewritten for the same pixel.
struct MapPixel: Equatable { var x: Int; var y: Int }

/// The pointer's pixel over a picture, nothing else (the element maps); a drag here is the viewport's pan.
private struct HoverReader: View {
    let scanWidth: Int
    let scanHeight: Int
    let onHover: ((x: Int, y: Int)?) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear.contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): onHover(RegionDrawing.pixel(at: p, in: geo.size, scanWidth: scanWidth, scanHeight: scanHeight))
                    case .ended: onHover(nil)
                    }
                }
        }
    }
}

extension MapTileView where Overlay == EmptyView {
    /// A tile with nothing of the app's drawn over its picture.
    public init(title: String, detail: String? = nil, image: CGImage?, size: CGSize, scanWidth: Int, scanHeight: Int,
                pixelSize: Double? = nil, pixelUnit: String? = nil, regions: MapTileRegions? = nil, filteredTag: Bool = false,
                inMix: Bool? = nil, onToggleMix: (() -> Void)? = nil, placeholder: String? = nil, transform: Binding<MapViewTransform> = .constant(MapViewTransform()),
                onHover: @escaping ((x: Int, y: Int)?) -> Void,
                @ViewBuilder controls: () -> Controls) {
        self.init(title: title, detail: detail, image: image, size: size, scanWidth: scanWidth, scanHeight: scanHeight, pixelSize: pixelSize, pixelUnit: pixelUnit,
                  regions: regions, filteredTag: filteredTag, inMix: inMix, onToggleMix: onToggleMix, placeholder: placeholder, transform: transform,
                  onHover: onHover, controls: controls, overlay: { _ in EmptyView() })
    }
}
