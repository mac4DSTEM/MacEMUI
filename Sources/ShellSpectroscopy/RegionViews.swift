//
//  RegionViews.swift
//  Role: the outline overlay a map tile draws over its image, read from a `SpectralRegionSet`; the drawing tools that make the shapes stay with the tile.
//

import SwiftUI
import ShellInspector

/// The visible regions' outlines over a map tile, in their colours (the selected one drawn heavier), with an optional marker for the pixel under the
/// pointer. The view is as large as the image it covers: `scanWidth` x `scanHeight` pixels map to its frame.
public struct RegionOverlay: View {
    private let regions: [SpectralRegion]
    private let selectedID: UUID?
    private let scanWidth: Int
    private let scanHeight: Int
    private let pixel: (x: Int, y: Int)?
    private let strokeScale: CGFloat

    /// `strokeScale` is 1 over the zoom of the picture the overlay is drawn in, so outlines keep their weight when the picture is scaled up.
    public init(set: SpectralRegionSet, scanWidth: Int, scanHeight: Int, pixel: (x: Int, y: Int)? = nil, strokeScale: CGFloat = 1) {
        self.strokeScale = strokeScale
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
                let width: CGFloat = (region.id == selectedID ? 2.5 : 1.5) * strokeScale
                // A dark under-stroke keeps the colour readable on bright pixels.
                context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: width + 1.5 * strokeScale)
                context.stroke(path, with: .color(region.color.color), lineWidth: width)
            }
            if let pixel {
                let r = CGRect(x: Double(pixel.x) * sx, y: Double(pixel.y) * sy, width: max(sx, 3 * strokeScale), height: max(sy, 3 * strokeScale))
                context.stroke(Path(r), with: .color(.black.opacity(0.55)), lineWidth: 2.5 * strokeScale)
                context.stroke(Path(r), with: .color(.white), lineWidth: 1 * strokeScale)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
