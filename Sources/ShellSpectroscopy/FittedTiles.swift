//
//  FittedTiles.swift
//  Role: the maps block of a spectroscopy room that scales with its panes (design 2026-10-22, corrected EDS room): the tiles are laid out in the space they are given, as large as
//        they can be, with no size to choose; drag a divider and they follow. `FittedTileLayout` is the pure arithmetic (a test holds it), `FittedMapGrid` the view, `HorizontalPaneSplit` the
//        divider between an anchor tile and the grid.
//

import SwiftUI
import ShellControls
import ShellLayout

public nonisolated enum FittedTileLayout {
    /// The grid that gives `count` tiles of one aspect ratio (width / height of the picture) the largest size inside `container`: the number of columns, and each tile's size. `spacing`
    /// is the gap between tiles. Ties keep the fewer columns (a taller grid reads top to bottom). Zero tiles or an empty container give a zero layout.
    public static func best(count: Int, aspect: CGFloat, in container: CGSize, spacing: CGFloat = 8) -> (columns: Int, tile: CGSize) {
        guard count > 0, aspect > 0, container.width > 0, container.height > 0 else { return (1, .zero) }
        var best: (columns: Int, tile: CGSize) = (1, .zero)
        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            let widthLimit = (container.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let heightLimit = (container.height - CGFloat(rows - 1) * spacing) / CGFloat(rows) * aspect
            let width = min(widthLimit, heightLimit)
            guard width > 0 else { continue }
            if width > best.tile.width + 0.5 { best = (columns, CGSize(width: width.rounded(.down), height: (width / aspect).rounded(.down))) }
        }
        return best
    }
}

/// The tiles in the space given, as large as they fit; a double click shows one alone, another returns the grid. Every tile has the same picture aspect (a scan grid).
public struct FittedMapGrid<Item: Identifiable, Tile: View>: View {
    private let items: [Item]
    private let aspect: CGFloat
    private let spacing: CGFloat
    private let soloEnabled: Bool
    @Binding private var solo: Item.ID?
    private let tile: (Item, CGSize) -> Tile

    /// `tile` receives the item and the size its picture should have; it draws its own chrome (title, scale bar) inside that size.
    public init(items: [Item], aspect: CGFloat, solo: Binding<Item.ID?>, soloEnabled: Bool = true, spacing: CGFloat = 8,
                @ViewBuilder tile: @escaping (Item, CGSize) -> Tile) {
        self.items = items; self.aspect = aspect; self._solo = solo; self.soloEnabled = soloEnabled; self.spacing = spacing; self.tile = tile
    }

    public var body: some View {
        GeometryReader { geo in
            let shown = solo.flatMap { id in items.first { $0.id == id } }.map { [$0] } ?? items
            let area = CGSize(width: max(geo.size.width - 2 * spacing, 1), height: max(geo.size.height - 2 * spacing, 1))
            let layout = FittedTileLayout.best(count: shown.count, aspect: aspect, in: area, spacing: spacing)
            // One flat ForEach in a layout of its own: a tile keeps its identity (and its made picture) when a resize changes the number of columns; rows of nested stacks would rebuild it.
            FittedGridLayout(columns: layout.columns, tile: layout.tile, spacing: spacing) {
                ForEach(shown) { item in
                    tile(item, layout.tile)
                        .frame(width: layout.tile.width, height: layout.tile.height)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            if solo != nil { solo = nil } else if soloEnabled { solo = item.id }
                        })
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Places its subviews in rows of `columns` tiles of one size, the block centred in the bounds.
struct FittedGridLayout: Layout {
    var columns: Int
    var tile: CGSize
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard columns > 0, !subviews.isEmpty else { return }
        let rows = (subviews.count + columns - 1) / columns
        let width = CGFloat(columns) * tile.width + CGFloat(columns - 1) * spacing
        let height = CGFloat(rows) * tile.height + CGFloat(rows - 1) * spacing
        let origin = CGPoint(x: bounds.minX + (bounds.width - width) / 2, y: bounds.minY + (bounds.height - height) / 2)
        for (i, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: origin.x + CGFloat(i % columns) * (tile.width + spacing), y: origin.y + CGFloat(i / columns) * (tile.height + spacing)),
                       anchor: .topLeading, proposal: ProposedViewSize(tile))
        }
    }
}

/// An anchor pane beside a main pane with a divider the person drags (the vertical twin of `VerticalPaneSplit`'s axis): the maps block's ColorMix beside the element maps.
public struct HorizontalPaneSplit<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing
    private let resizeLabel: String
    private let leadingName: String
    private let minimumLeading: CGFloat
    private let minimumTrailing: CGFloat
    @SceneStorage private var storedFraction: Double
    @State private var fractionAtDragStart: CGFloat?

    public init(storageKey: String, defaultFraction: Double = 0.3, resizeLabel: String = "Resize the panes", leadingName: String = "Leading pane",
                minimumLeading: CGFloat = 140, minimumTrailing: CGFloat = 240,
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading(); self.trailing = trailing()
        self.resizeLabel = resizeLabel; self.leadingName = leadingName
        self.minimumLeading = minimumLeading; self.minimumTrailing = minimumTrailing
        self._storedFraction = SceneStorage(wrappedValue: defaultFraction, storageKey)
    }

    private var fraction: CGFloat {
        get { CGFloat(storedFraction) }
        nonmutating set { storedFraction = Double(newValue) }
    }

    /// The leading pane's smallest and largest share of `usable` points (each pane keeps its floor; below two floors the split halves).
    public nonisolated static func bounds(usable: CGFloat, minimumLeading: CGFloat, minimumTrailing: CGFloat) -> (smallest: CGFloat, largest: CGFloat) {
        guard usable > minimumLeading + minimumTrailing else { return (0.5, 0.5) }
        return (minimumLeading / usable, 1 - minimumTrailing / usable)
    }

    public var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - 1, 1)
            let limits = Self.bounds(usable: usable, minimumLeading: minimumLeading, minimumTrailing: minimumTrailing)
            let clamped = min(max(fraction, limits.smallest), limits.largest)
            let leadingWidth = (usable * clamped).rounded()
            HStack(spacing: 0) {
                leading.frame(width: leadingWidth).clipped()
                divider(usable: usable, limits: limits)
                trailing.frame(width: usable - leadingWidth).clipped()
            }
        }
    }

    private func divider(usable: CGFloat, limits: (smallest: CGFloat, largest: CGFloat)) -> some View {
        Divider()
            .contentShape(Rectangle().inset(by: -LayoutPolicy.dividerGrabWidth / 2))
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = fractionAtDragStart ?? fraction
                        fractionAtDragStart = start
                        fraction = min(max(start + value.translation.width / usable, limits.smallest), limits.largest)
                    }
                    .onEnded { _ in fractionAtDragStart = nil }
            )
            .accessibilityLabel(resizeLabel)
            .accessibilityValue("\(leadingName) \(Int((min(max(fraction, limits.smallest), limits.largest) * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(DividerNudge.step, usable: usable, limits: limits)
                case .decrement: nudge(-DividerNudge.step, usable: usable, limits: limits)
                @unknown default: break
                }
            }
            .focusable(interactions: .activate)
            .onMoveCommand { direction in
                switch direction {
                case .right: nudge(DividerNudge.step, usable: usable, limits: limits)
                case .left: nudge(-DividerNudge.step, usable: usable, limits: limits)
                default: break
                }
            }
    }

    private func nudge(_ points: CGFloat, usable: CGFloat, limits: (smallest: CGFloat, largest: CGFloat)) {
        guard usable > 0 else { return }
        let start = min(max(fraction, limits.smallest), limits.largest)
        fraction = min(max(start + points / usable, limits.smallest), limits.largest)
    }
}

/// The maps block of the corrected room: an anchor tile (the ColorMix, where regions are drawn) on the leading side and the element maps fitted into the rest, a divider between them,
/// both scaling with the panes. A double click on any tile shows it alone; another returns. With no anchor the maps fill the block. The tile view is told whether it is the anchor.
public struct AnchoredMapsBlock<Item: Identifiable, Tile: View>: View {
    private let anchor: Item?
    private let items: [Item]
    private let aspect: CGFloat
    private let storageKey: String
    @Binding private var solo: Item.ID?
    private let soloEnabled: Bool
    private let tile: (Item, CGSize, Bool) -> Tile

    public init(anchor: Item?, items: [Item], aspect: CGFloat, storageKey: String, solo: Binding<Item.ID?>, soloEnabled: Bool = true,
                @ViewBuilder tile: @escaping (Item, CGSize, Bool) -> Tile) {
        self.anchor = anchor; self.items = items; self.aspect = aspect; self.storageKey = storageKey; self._solo = solo; self.soloEnabled = soloEnabled; self.tile = tile
    }

    public var body: some View {
        if let id = solo, let item = ([anchor].compactMap { $0 } + items).first(where: { $0.id == id }) {
            FittedMapGrid(items: [item], aspect: aspect, solo: $solo, soloEnabled: soloEnabled) { item, size in tile(item, size, item.id == anchor?.id) }
        } else if let anchor {
            HorizontalPaneSplit(storageKey: storageKey, defaultFraction: 0.32, resizeLabel: "Resize the colour mix and the maps", leadingName: "Colour mix",
                                minimumLeading: 160, minimumTrailing: 260) {
                FittedMapGrid(items: [anchor], aspect: aspect, solo: $solo, soloEnabled: soloEnabled) { item, size in tile(item, size, true) }
            } trailing: {
                FittedMapGrid(items: items, aspect: aspect, solo: $solo, soloEnabled: soloEnabled) { item, size in tile(item, size, false) }
            }
        } else {
            FittedMapGrid(items: items, aspect: aspect, solo: $solo, soloEnabled: soloEnabled) { item, size in tile(item, size, false) }
        }
    }
}
