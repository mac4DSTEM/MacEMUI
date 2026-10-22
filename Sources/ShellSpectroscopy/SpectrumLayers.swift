//
//  SpectrumLayers.swift
//  Role: several spectra on one plot (design 2026-10-22 §2.2): one layer per region, in the region's colour, and a temporary pixel layer under the pointer.
//        The room's own Canvas keeps its axes, lines, zoom and fit curves; it calls `SpectrumLayerPlot.draw` for the layers and `SpectrumLayerLegend`
//        for the names. The numbers in a layer are the kit's (a pooled sum, a pixel); this file only maps them to the plot and thins them to its width.
//

import SwiftUI

/// One spectrum to draw: counts on an equally spaced axis starting at `origin` with `step` per channel (eV, keV or whatever the room's axis is in).
public nonisolated struct SpectrumLayer: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var color: RegionColor
    public var origin: Double
    public var step: Double
    public var counts: [Double]
    /// The pixel under the pointer is drawn dashed: it is passing, not a region.
    public var isTemporary: Bool

    public init(id: String, name: String, color: RegionColor, origin: Double, step: Double, counts: [Double], isTemporary: Bool = false) {
        self.id = id; self.name = name; self.color = color; self.origin = origin; self.step = step; self.counts = counts; self.isTemporary = isTemporary
    }

    /// The axis value of channel `i`.
    public func position(of channel: Int) -> Double { origin + Double(channel) * step }
}

/// How counts map to the plot's vertical axis.
public nonisolated enum SpectrumScale: String, CaseIterable, Identifiable, Sendable {
    case linear, log

    public var id: String { rawValue }
    public var title: String { self == .linear ? "Linear" : "Log" }

    /// The plotted value of `count`: itself, or log10 with a floor of 1 count (a zero-count channel sits at 0, not at minus infinity).
    public func transform(_ count: Double) -> Double { self == .linear ? count : Foundation.log10(max(count, 1)) }
}

public nonisolated enum SpectrumLayerPlot {
    /// One plotted column: the lowest and highest transformed value among the channels that fall in it, so a narrow peak never vanishes when thinned.
    public struct Column: Equatable, Sendable {
        public var x: Double
        public var low: Double, high: Double
    }

    /// The layer thinned to at most `columns` columns across `xRange`: each holds the min and max of the channels it covers (min-max decimation). When
    /// there are fewer channels than columns each channel is its own column.
    public static func columns(of layer: SpectrumLayer, in xRange: ClosedRange<Double>, columns: Int, scale: SpectrumScale,
                               normalizedBy norm: Double = 1) -> [Column] {
        guard layer.step != 0, !layer.counts.isEmpty, columns > 0, xRange.upperBound > xRange.lowerBound else { return [] }
        let last = layer.counts.count - 1
        func channel(_ x: Double) -> Int { Int(((x - layer.origin) / layer.step).rounded()) }
        let lo = max(min(channel(xRange.lowerBound), channel(xRange.upperBound)), 0)
        let hi = min(max(channel(xRange.lowerBound), channel(xRange.upperBound)), last)
        guard lo <= hi else { return [] }
        let channels = hi - lo + 1
        let n = min(columns, channels)
        var out: [Column] = []
        out.reserveCapacity(n)
        for k in 0..<n {
            let from = lo + k * channels / n, to = lo + (k + 1) * channels / n   // [from, to)
            var low = Double.infinity, high = -Double.infinity
            for i in from..<max(to, from + 1) {
                let v = scale.transform(layer.counts[i] / norm)
                low = min(low, v); high = max(high, v)
            }
            let mid = layer.position(of: from) + (layer.position(of: max(to, from + 1) - 1) - layer.position(of: from)) / 2
            out.append(Column(x: mid, low: low, high: high))
        }
        return out
    }

    /// The largest transformed value over the layers in `xRange` (the plot's top when the room does not choose one); nil when no layer has a channel there.
    public static func peak(of layers: [SpectrumLayer], in xRange: ClosedRange<Double>, scale: SpectrumScale, normalized: Bool = false) -> Double? {
        var best: Double?
        for layer in layers where layer.step != 0 && !layer.counts.isEmpty {
            let norm = normalized ? normalizer(of: layer, in: xRange) : 1
            for c in columns(of: layer, in: xRange, columns: layer.counts.count, scale: scale, normalizedBy: norm) { best = max(best ?? c.high, c.high) }
        }
        return best
    }

    /// The count that scales a layer to 1 in `xRange` when layers are compared by shape (regions of different size pool different counts); 1 for an empty layer.
    public static func normalizer(of layer: SpectrumLayer, in xRange: ClosedRange<Double>) -> Double {
        guard layer.step != 0, !layer.counts.isEmpty else { return 1 }
        let a = Int(((xRange.lowerBound - layer.origin) / layer.step).rounded()), b = Int(((xRange.upperBound - layer.origin) / layer.step).rounded())
        let lo = max(min(a, b), 0), hi = min(max(a, b), layer.counts.count - 1)
        guard lo <= hi else { return 1 }
        let m = layer.counts[lo...hi].max() ?? 1
        return m > 0 ? m : 1
    }

    /// Draws the layers into `rect`: x from `xRange`, y from 0 to `top` (transformed values). Regions are solid lines, a temporary layer is dashed, and a dark
    /// under-stroke keeps each readable over the room's grid.
    public static func draw(_ layers: [SpectrumLayer], in context: inout GraphicsContext, rect: CGRect, xRange: ClosedRange<Double>, top: Double,
                            scale: SpectrumScale, normalized: Bool = false) {
        guard top > 0, xRange.upperBound > xRange.lowerBound else { return }
        let columnCount = max(Int(rect.width), 1)
        for layer in layers {
            let norm = normalized ? normalizer(of: layer, in: xRange) : 1
            let cols = columns(of: layer, in: xRange, columns: columnCount, scale: scale, normalizedBy: norm)
            guard !cols.isEmpty else { continue }
            func point(_ x: Double, _ v: Double) -> CGPoint {
                CGPoint(x: rect.minX + (x - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound) * rect.width,
                        y: rect.maxY - min(max(v / top, 0), 1) * rect.height)
            }
            var path = Path()
            for (i, c) in cols.enumerated() {
                let p = point(c.x, c.high)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                if c.low < c.high { path.addLine(to: point(c.x, c.low)); path.addLine(to: p) }
            }
            let style = StrokeStyle(lineWidth: 1.2, lineJoin: .round, dash: layer.isTemporary ? [4, 3] : [])
            context.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 2.4, lineJoin: .round, dash: layer.isTemporary ? [4, 3] : []))
            context.stroke(path, with: .color(layer.color.color), style: style)
        }
    }
}

/// The layers' names with their colours, one row per layer: what the plot's lines are. Compact enough for the strip's header.
public struct SpectrumLayerLegend: View {
    private let layers: [SpectrumLayer]

    public init(layers: [SpectrumLayer]) {
        self.layers = layers
    }

    public var body: some View {
        HStack(spacing: 10) {
            ForEach(layers) { layer in
                HStack(spacing: 4) {
                    Capsule().fill(layer.color.color).frame(width: 14, height: layer.isTemporary ? 2 : 3)
                        .overlay { if layer.isTemporary { Capsule().stroke(Color.primary.opacity(0.4), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])) } }
                    Text(layer.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("spectrum.legend.\(layer.id)")
            }
        }
        .accessibilityIdentifier("spectrum.legend")
    }
}
