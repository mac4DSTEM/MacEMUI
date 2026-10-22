//
//  MapTiles.swift
//  Role: the maps block of a spectroscopy room (design 2026-10-22 §2.4): the tile grid that reflows to a chosen tile size, shows one tile alone on a
//        double click (and returns on the next), and the pointer's value as a chip on the tile. The tile's own drawing, its colour bar and its
//        region overlay are the app's; the layout, the size choice and the solo gesture are shared.
//

import SwiftUI

/// How large a map tile is drawn: the grid reflows to it. The widths are the adaptive grid's bounds, in points.
public nonisolated enum MapTileSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The adaptive column's narrowest and widest tile.
    public var widths: (min: CGFloat, max: CGFloat) {
        switch self {
        case .small: (150, 200)
        case .medium: (220, 320)
        case .large: (340, 520)
        }
    }

    /// How many tiles of this size fit one row of `width` points, with `spacing` between them (what the grid shows; pure, so a test holds it).
    public func columns(in width: CGFloat, spacing: CGFloat = 8) -> Int {
        max(Int(((width + spacing) / (widths.min + spacing)).rounded(.down)), 1)
    }
}

/// The size choice as one inspector row's control: a three-segment picker.
public struct MapTileSizePicker: View {
    @Binding private var selection: MapTileSize

    public init(selection: Binding<MapTileSize>) {
        self._selection = selection
    }

    public var body: some View {
        Picker("Tile size", selection: $selection) {
            ForEach(MapTileSize.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("maps.tileSize")
    }
}

/// The tiles of a room in an adaptive grid of the chosen size. `solo` names one tile to show alone, filling the block; a double click on a tile sets
/// it, and a double click on the solo tile returns the grid. The app's tile view takes whatever width the grid gives it.
public struct MapTileGrid<Item: Identifiable, Tile: View>: View {
    private let items: [Item]
    private let size: MapTileSize
    private let spacing: CGFloat
    private let soloEnabled: Bool
    @Binding private var solo: Item.ID?
    private let tile: (Item) -> Tile

    /// `soloEnabled: false` leaves the double click to the tile (a polygon tool's vertices are clicks); an open solo tile still returns on a double click.
    public init(items: [Item], size: MapTileSize, solo: Binding<Item.ID?>, soloEnabled: Bool = true, spacing: CGFloat = 8,
                @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.size = size
        self._solo = solo
        self.soloEnabled = soloEnabled
        self.spacing = spacing
        self.tile = tile
    }

    public var body: some View {
        if let id = solo, let item = items.first(where: { $0.id == id }) {
            tile(item)
                .padding(spacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .simultaneousGesture(TapGesture(count: 2).onEnded { solo = nil })
                .accessibilityHint("Double click to show all maps")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: size.widths.min, maximum: size.widths.max), spacing: spacing, alignment: .top)],
                          alignment: .leading, spacing: spacing) {
                    ForEach(items) { item in
                        tile(item)
                            .simultaneousGesture(TapGesture(count: 2).onEnded { if soloEnabled { solo = item.id } })
                    }
                }
                .padding(spacing)
            }
        }
    }
}

extension View {
    /// The pointer's value on a tile (design §2.3): a small chip at the bottom leading corner, e.g. "Mg 36.2 at%". Nothing when `text` is nil. It
    /// never takes the pointer, so hovering through it keeps reading the pixel under it.
    public func hoverChip(_ text: String?) -> some View {
        overlay(alignment: .bottomLeading) {
            if let text {
                Text(verbatim: text)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    // Legibility plate over arbitrary map data, as the scale bar's.
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("maps.hoverChip")
            }
        }
    }
}
