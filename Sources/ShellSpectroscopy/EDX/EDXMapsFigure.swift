//
//  EDXMapsFigure.swift
//  Role: the maps as one PNG (the Export section's "Maps as PNG…"): the shown tiles in a grid, each with its title, the regions
//        where the room draws them (every shown pin and line on the colour mix, in its own colour; on every tile when the figure
//        has no mix), a scale bar from the file's pixel size and, for a composition tile, the footer that carries the
//        factor source. The picture is a SwiftUI view rendered by `ImageRenderer`; the pixels of a
//        tile are `EDXMapRaster`'s, the bar's numbers ImagoKit's (`EDXExports.scaleBar`). Presentation only.
//

import SwiftUI
import SpectroCore
import SpectroEDX
import ImageIO
import UniformTypeIdentifiers
import ShellEDXModel

/// One picture of the figure made by its room (the EELS room's maps and colour mix): the title, the detail beside it, the RGBA pixels and the footer.
public struct EDXFigureCell: Identifiable {
    public private(set) var id: String
    public private(set) var title: String
    package private(set) var detail: String
    public private(set) var rgba: [UInt8]
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var footer: String?

    public init(id: String, title: String, detail: String, rgba: [UInt8], width: Int, height: Int, footer: String?) {
        self.id = id; self.title = title; self.detail = detail; self.rgba = rgba; self.width = width; self.height = height; self.footer = footer
    }
}

/// What the figure draws; a plain value so a test can build one without a session.
public struct EDXFigureContent {
    public private(set) var title: String
    package private(set) var subtitle: String
    public private(set) var tiles: [EDXMapTile]
    public private(set) var region: EDXRegion
    public private(set) var nx: Int
    public private(set) var ny: Int
    package private(set) var bar: (fraction: Double, label: String)?
    /// The maps in the colour mix; drawn as the first tile when there are any.
    public private(set) var mix: [EDXMapTile] = []
    /// Whether the scale bar and the selected region are drawn (the export's two toggles).
    package private(set) var showsScaleBar = true
    package private(set) var showsRegion = true
    /// Pictures another room made (the EELS maps, its colour mix first), drawn after the EDS tiles with the same frame, region and scale bar.
    package private(set) var cells: [EDXFigureCell] = []
    /// The room's pins and lines as its colour mix draws them (hidden ones stay hidden, the selected one heavier). nil: only `region`, in white, on every tile.
    public private(set) var regions: SpectralRegionSet?

    public init(title: String, subtitle: String, tiles: [EDXMapTile], region: EDXRegion, nx: Int, ny: Int, bar: (fraction: Double, label: String)?,
                mix: [EDXMapTile] = [], showsScaleBar: Bool = true, showsRegion: Bool = true, cells: [EDXFigureCell] = [], regions: SpectralRegionSet? = nil) {
        self.title = title; self.subtitle = subtitle; self.tiles = tiles; self.region = region; self.nx = nx; self.ny = ny; self.bar = bar
        self.mix = mix; self.showsScaleBar = showsScaleBar; self.showsRegion = showsRegion; self.cells = cells; self.regions = regions
    }

    /// Whether a tile draws the regions: with the room's set, the colour mix only (as in the room), or every tile when the figure has no mix;
    /// without it, every tile (the selected region).
    package func drawsRegions(onMix isMix: Bool) -> Bool {
        guard showsRegion else { return false }
        guard regions != nil else { return true }
        return isMix || mix.isEmpty
    }
}

public struct EDXMapsFigure: View {
    let content: EDXFigureContent

    public init(content: EDXFigureContent) { self.content = content }
    static let cellWidth: CGFloat = 300
    static let columns = 3

    public var body: some View {
        let cols = max(1, min(Self.columns, content.tiles.count + content.cells.count))
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title).font(.headline)
                Text(content.subtitle).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cellWidth), spacing: 10, alignment: .top), count: cols), alignment: .leading, spacing: 12) {
                if !content.mix.isEmpty { mixCell }
                ForEach(content.tiles) { tile in cell(tile) }
                ForEach(content.cells) { c in cell(c) }
            }
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(Color(white: 0.11))
        .environment(\.colorScheme, .dark)
    }

    private var mixCell: some View {
        let first = content.mix[0]
        let layers = content.mix.map { MapRaster.MixLayer(values: $0.values, color: EDXRegionBridge.defaultColoring($0.symbol).endColor) }
        let image = EDXMapRaster.cgImage(rgba: MapRaster.mix(layers, count: first.values.count), width: first.width, height: first.height)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Colour mix").font(.callout.weight(.semibold))
                Text(content.mix.map(\.symbol).joined(separator: " + ")).font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            Color.black
                .aspectRatio(CGFloat(max(first.width, 1)) / CGFloat(max(first.height, 1)), contentMode: .fit)
                .overlay { if let image { Image(decorative: image, scale: 1).interpolation(.none).resizable() } }
                .overlay { GeometryReader { geo in overlay(size: geo.size, isMix: true) } }
        }
        .frame(width: Self.cellWidth, alignment: .leading)
    }

    private func cell(_ tile: EDXMapTile) -> some View {
        let image = EDXMapRaster.cgImage(rgba: EDXMapRaster.rgba(values: tile.values, hue: EDXRoomFormat.hue(symbol: tile.symbol), width: tile.width),
                                         width: tile.width, height: tile.height)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tile.symbol).font(.callout.weight(.semibold))
                Text(tile.line).font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            Color.black
                .aspectRatio(CGFloat(max(tile.width, 1)) / CGFloat(max(tile.height, 1)), contentMode: .fit)
                .overlay { if let image { Image(decorative: image, scale: 1).interpolation(.none).resizable() } }
                .overlay { GeometryReader { geo in overlay(size: geo.size) } }
            if let footer = tile.footer {
                Text(footer).font(.caption2).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Self.cellWidth, alignment: .leading)
    }

    private func cell(_ c: EDXFigureCell) -> some View {
        let image = EDXMapRaster.cgImage(rgba: c.rgba, width: c.width, height: c.height)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(c.title).font(.callout.weight(.semibold))
                Text(c.detail).font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            Color.black
                .aspectRatio(CGFloat(max(c.width, 1)) / CGFloat(max(c.height, 1)), contentMode: .fit)
                .overlay { if let image { Image(decorative: image, scale: 1).interpolation(.none).resizable() } }
                .overlay { GeometryReader { geo in overlay(size: geo.size) } }
            if let footer = c.footer {
                Text(footer).font(.caption2).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Self.cellWidth, alignment: .leading)
    }

    private func overlay(size: CGSize, isMix: Bool = false) -> some View {
        ZStack(alignment: .bottomLeading) {
            if content.drawsRegions(onMix: isMix) {
                if let set = content.regions {
                    RegionOverlay(set: set, scanWidth: content.nx, scanHeight: content.ny)
                } else if let outline = EDXMapOutline.outline(of: content.region, in: size, nx: content.nx, ny: content.ny) {
                    outline.stroke(.white, lineWidth: 1.5)
                }
            }
            if content.showsScaleBar, let bar = content.bar {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bar.label).font(.caption2.monospaced())
                    Rectangle().frame(width: size.width * bar.fraction, height: EDXLayout.figureBarThickness)
                }
                .padding(6)
                .background(.black.opacity(0.45))
                .padding(6)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
    }

    /// The figure as an image at 2× (mac4DSTEM: the window's figure export takes it as one panel), or nil if the renderer made none.
    @MainActor public static func cgImage(_ content: EDXFigureContent) -> CGImage? {
        let renderer = ImageRenderer(content: EDXMapsFigure(content: content))
        renderer.scale = 2
        return renderer.cgImage
    }

    /// The PNG of the figure at 2×, or nil if the renderer made no image.
    @MainActor public static func png(_ content: EDXFigureContent) -> Data? {
        guard let image = cgImage(content) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}

extension EDXSession {
    /// The room's pins and lines; a selected region that is no pin (a shape not kept) joins them in white, as the figure drew it before.
    func figureRegions(linesFocused: Bool) -> SpectralRegionSet {
        var set = EDXRegionBridge.set(self, linesFocused: linesFocused)
        if selectedPin == nil, let g = EDXRegionBridge.geometry(region) {
            let id = UUID()
            set = SpectralRegionSet(regions: set.regions + [SpectralRegion(id: id, name: "Selected", color: RegionColor(red: 1, green: 1, blue: 1), isVisible: true, geometry: g)],
                                    selectedID: linesFocused ? set.selectedID : id)
        }
        return set
    }

    /// What "Maps as PNG…" draws: the tiles the grid shows, the pins and lines as the colour mix shows them, the file's scale bar.
    /// `linesFocused` says whether the selection (drawn heavier) is a line, as the room's state does.
    public func figureContent(scaleBar: Bool = true, regions: Bool = true, mix: [EDXMapTile] = [], linesFocused: Bool = false) -> EDXFigureContent? {
        guard let source else { return nil }
        let m = source.metadata
        return EDXFigureContent(title: fileName,
                                subtitle: EDXRoomFormat.region(region, pixels: regionPixels) + " \u{00B7} " + (mapMode == .net ? "net counts" : mapMode.title),
                                tiles: shownTiles, region: region, nx: source.nx, ny: source.ny,
                                bar: EDXExports.scaleBar(pixelSize: m.scanPixelSize, unit: m.scanPixelUnit, nx: source.nx, ny: source.ny),
                                mix: mix, showsScaleBar: scaleBar, showsRegion: regions,
                                regions: figureRegions(linesFocused: linesFocused))
    }
}
