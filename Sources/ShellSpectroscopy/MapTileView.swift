//
//  MapTileView.swift
//  Role: one map of a spectroscopy room as the corrected design draws it (2026-10-22): the picture at the size the grid gives it, its name in the corner, a calibrated scale bar that opens
//        the map's colour controls, the colour scale and the pointer's value while the pointer is over it, ONE cursor (only the tile under the pointer marks the pixel), and, on the anchor
//        tile only, the regions and the tools that draw and edit them. The picture itself (the pixels) and the numbers are the app's; this is the frame.
//

import ShellControls
import ShellMetal
import SwiftUI

/// What a tile's colour scale shows: black (or the colormap's start) at `low`, the full colour at `high`, in `unit`.
public struct MapColorbarSpec: Equatable, Sendable {
    public var low: Double
    public var high: Double
    public var unit: String
    public var coloring: MapColoring

    public init(low: Double, high: Double, unit: String, coloring: MapColoring) {
        self.low = low; self.high = high; self.unit = unit; self.coloring = coloring
    }
}

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

    public init(set: SpectralRegionSet, tool: RegionTool,
                onRectangle: @escaping (Int, Int, Int, Int) -> Void, onEllipse: @escaping (Int, Int, Int, Int) -> Void,
                onPolygon: @escaping ([RegionPoint]) -> Void, onLine: @escaping (RegionPoint, RegionPoint) -> Void,
                onEdit: @escaping (UUID, RegionGeometry) -> Void, onDrag: @escaping (RegionDragUpdate?) -> Void = { _ in }) {
        self.set = set; self.tool = tool
        self.onRectangle = onRectangle; self.onEllipse = onEllipse; self.onPolygon = onPolygon; self.onLine = onLine; self.onEdit = onEdit; self.onDrag = onDrag
    }
}

public struct MapTileView<Controls: View>: View {
    private let title: String
    private let detail: String?
    private let image: CGImage?
    private let size: CGSize
    private let scanWidth: Int
    private let scanHeight: Int
    private let pixelSize: Double?
    private let pixelUnit: String?
    private let colorbar: MapColorbarSpec?
    private let regions: MapTileRegions?
    private let valueText: (Int, Int) -> String?
    private let onHover: ((x: Int, y: Int)?) -> Void
    private let controls: Controls
    @State private var local: (x: Int, y: Int)?
    @State private var showControls = false

    /// - `pixelSize` / `pixelUnit`: the scan's real-space step ("nm") for the scale bar; nil draws the bar in scan pixels.
    /// - `regions`: set on the anchor tile only. `valueText`: the pointer's value as the chip words it ("Mg 36.2 net counts"); nil where the pixel has none.
    /// - `controls`: the content of the popover the scale bar opens (the map's colour, histogram and gamma).
    public init(title: String, detail: String? = nil, image: CGImage?, size: CGSize, scanWidth: Int, scanHeight: Int,
                pixelSize: Double? = nil, pixelUnit: String? = nil, colorbar: MapColorbarSpec? = nil, regions: MapTileRegions? = nil,
                valueText: @escaping (Int, Int) -> String?, onHover: @escaping ((x: Int, y: Int)?) -> Void,
                @ViewBuilder controls: () -> Controls) {
        self.title = title; self.detail = detail; self.image = image; self.size = size; self.scanWidth = scanWidth; self.scanHeight = scanHeight
        self.pixelSize = pixelSize; self.pixelUnit = pixelUnit; self.colorbar = colorbar; self.regions = regions
        self.valueText = valueText; self.onHover = onHover; self.controls = controls()
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let image { Image(decorative: image, scale: 1).interpolation(.none).resizable() }
            // The regions and their tools (anchor tile) or just the hover (every other tile). Only the tile under the pointer draws the cursor.
            if let regions {
                RegionDrawingLayer(tool: regions.tool, set: regions.set, scanWidth: scanWidth, scanHeight: scanHeight, pointer: local.map { (x: $0.x, y: $0.y) },
                                   onRectangle: regions.onRectangle, onEllipse: regions.onEllipse, onPolygon: regions.onPolygon, onLine: regions.onLine,
                                   onHover: { pixel in local = pixel.map { (x: $0.x, y: $0.y) }; onHover(pixel) }, onEdit: regions.onEdit, onDrag: regions.onDrag)
            } else {
                HoverReader(scanWidth: scanWidth, scanHeight: scanHeight) { pixel in local = pixel.map { (x: $0.x, y: $0.y) }; onHover(pixel) }
                RegionOverlay(set: SpectralRegionSet(), scanWidth: scanWidth, scanHeight: scanHeight, pixel: local.map { (x: $0.x, y: $0.y) })
            }
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .padding(6)
                .allowsHitTesting(false)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.8)).shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .padding(.leading, 6).padding(.top, 20).allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomLeading) { scaleBar }
        .overlay(alignment: .bottomTrailing) {
            if local != nil, let colorbar { MapColorbarView(spec: colorbar).padding(6).allowsHitTesting(false).transition(.opacity) }
        }
        .overlay(alignment: .topTrailing) {
            if let local, let text = valueText(local.x, local.y) {
                Text(verbatim: text).font(.caption.monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(6).allowsHitTesting(false)
                    .accessibilityIdentifier("maps.hoverChip")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        // A hairline edge: a bright map would otherwise run into a light window.
        .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.separator) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(detail.map { "\(title) map, \($0)" } ?? "\(title) map")
    }

    private var scaleBar: some View {
        let perPoint = (pixelSize ?? 1) * Double(scanWidth) / max(Double(size.width), 1)
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

/// The pointer's pixel over a picture, nothing else (the element maps).
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

/// The colour scale of a map: its ramp with the two ends and the unit, on a legibility plate.
public struct MapColorbarView: View {
    private let spec: MapColorbarSpec

    public init(spec: MapColorbarSpec) { self.spec = spec }

    public var body: some View {
        VStack(spacing: 1) {
            LinearGradient(colors: Self.stops(spec.coloring), startPoint: .leading, endPoint: .trailing)
                .frame(width: 90, height: 5)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            HStack {
                Text(verbatim: Self.number(spec.low))
                Spacer(minLength: 6)
                Text(verbatim: "\(Self.number(spec.high)) \(spec.unit)")
            }
            .font(.system(size: 9, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(width: 106)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colour scale")
        .accessibilityValue("\(Self.number(spec.low)) to \(Self.number(spec.high)) \(spec.unit)")
        .accessibilityIdentifier("maps.colorbar")
    }

    nonisolated static func number(_ v: Double) -> String { v.formatted(.number.grouping(.never).precision(.significantDigits(1...4))) }

    static func stops(_ coloring: MapColoring) -> [Color] {
        switch coloring {
        case .color(let c): return [.black, c.color]
        case .colormap(let kind):
            let lut = Colormaps.lutRGBA(kind, count: 9)
            return (0..<9).map { Color(.sRGB, red: Double(lut[4 * $0]) / 255, green: Double(lut[4 * $0 + 1]) / 255, blue: Double(lut[4 * $0 + 2]) / 255, opacity: 1) }
        }
    }
}
