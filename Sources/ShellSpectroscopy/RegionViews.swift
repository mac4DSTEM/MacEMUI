//
//  RegionViews.swift
//  Role: the regions' two views (design 2026-10-22 §2.1): the list in the inspector (select, show or hide, rename, recolour, delete) and the outline overlay a
//        map tile draws over its image. Both read a `SpectralRegionSet`; the drawing tools that make the shapes stay with the app's tile.
//

import SwiftUI
import ShellInspector

/// The inspector's Regions list: one row per region with its colour (a picker), name (editable), kind, a show/hide eye and a delete button. A tap selects.
public struct RegionsList: View {
    @Binding private var set: SpectralRegionSet
    @Environment(\.self) private var environment

    public init(set: Binding<SpectralRegionSet>) {
        self._set = set
    }

    public var body: some View {
        if set.regions.isEmpty {
            InspectorNote("Draw a rectangle, ellipse, polygon or line on a map to compare regions.")
        } else {
            VStack(spacing: 2) {
                ForEach(set.regions) { region in row(region) }
            }
            .accessibilityIdentifier("regions.list")
        }
    }

    private func row(_ region: SpectralRegion) -> some View {
        let id = region.id
        let selected = set.selectedID == id
        return HStack(spacing: 6) {
            ColorPicker("Colour of \(region.name)", selection: Binding(
                get: { region.color.color },
                set: { set.setColor(id, RegionColor($0, resolvedIn: environment)) }), supportsOpacity: false)
                .labelsHidden()
                .accessibilityIdentifier("regions.color.\(region.name)")
            TextField("Name", text: Binding(get: { region.name }, set: { set.rename(id, to: $0) }))
                .textFieldStyle(.plain)
                .lineLimit(1)
                .opacity(region.isVisible ? 1 : 0.5)
                .accessibilityIdentifier("regions.name.\(region.name)")
            Text(region.geometry.kindName).font(.caption).foregroundStyle(.secondary)
            Button { set.setVisible(id, !region.isVisible) } label: {
                Image(systemName: region.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
            .help(region.isVisible ? "Hide \(region.name)" : "Show \(region.name)")
            .accessibilityLabel(region.isVisible ? "Hide \(region.name)" : "Show \(region.name)")
            .accessibilityIdentifier("regions.visibility.\(region.name)")
            Button { set.remove(id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete \(region.name)")
                .accessibilityLabel("Delete \(region.name)")
                .accessibilityIdentifier("regions.delete.\(region.name)")
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { set.select(id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("regions.row.\(region.name)")
    }
}

/// The visible regions' outlines over a map tile, in their colours (the selected one drawn heavier), with an optional marker for the pixel under the
/// pointer. The view is as large as the image it covers: `scanWidth` x `scanHeight` pixels map to its frame.
public struct RegionOverlay: View {
    private let regions: [SpectralRegion]
    private let selectedID: UUID?
    private let scanWidth: Int
    private let scanHeight: Int
    private let pixel: (x: Int, y: Int)?

    public init(set: SpectralRegionSet, scanWidth: Int, scanHeight: Int, pixel: (x: Int, y: Int)? = nil) {
        self.regions = set.visible
        self.selectedID = set.selectedID
        self.scanWidth = scanWidth
        self.scanHeight = scanHeight
        self.pixel = pixel
    }

    public var body: some View {
        Canvas { context, size in
            guard scanWidth > 0, scanHeight > 0 else { return }
            let sx = size.width / Double(scanWidth), sy = size.height / Double(scanHeight)
            func point(_ p: RegionPoint) -> CGPoint { CGPoint(x: p.x * sx, y: p.y * sy) }
            func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
                CGRect(x: min(x0, x1) * sx, y: min(y0, y1) * sy, width: abs(x1 - x0) * sx, height: abs(y1 - y0) * sy)
            }
            for region in regions {
                var path = Path()
                switch region.geometry {
                case .rectangle(let x0, let y0, let x1, let y1): path.addRect(box(x0, y0, x1, y1))
                case .ellipse(let x0, let y0, let x1, let y1): path.addEllipse(in: box(x0, y0, x1, y1))
                case .polygon(let v):
                    guard let first = v.first else { continue }
                    path.move(to: point(first)); for p in v.dropFirst() { path.addLine(to: point(p)) }; path.closeSubpath()
                case .line(let a, let b): path.move(to: point(a)); path.addLine(to: point(b))
                }
                let width: CGFloat = region.id == selectedID ? 2.5 : 1.5
                // A dark under-stroke keeps the colour readable on bright pixels.
                context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: width + 1.5)
                context.stroke(path, with: .color(region.color.color), lineWidth: width)
            }
            if let pixel {
                let r = CGRect(x: Double(pixel.x) * sx, y: Double(pixel.y) * sy, width: max(sx, 3), height: max(sy, 3))
                context.stroke(Path(r), with: .color(.black.opacity(0.55)), lineWidth: 2.5)
                context.stroke(Path(r), with: .color(.white), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
