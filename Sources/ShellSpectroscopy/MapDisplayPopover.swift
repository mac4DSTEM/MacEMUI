//
//  MapDisplayPopover.swift
//  Role: the popover a map tile's scale bar opens (the Spectroscopy room's display popover, one control for both apps): an element map's colour, the HAADF's colormap or the colour mix's
//        members, then the map's histogram with its contrast-window handles and a gamma slider. Values and bindings come in; it knows no model. `MapHistogram` bins a map's values (pure).
//

import ShellControls
import ShellInspector
import ShellMetal
import SwiftUI

/// The bins of a map's histogram, pure.
public nonisolated enum MapHistogram {
    /// `count` bins over `range` (nil: the finite values' own range), NaN and infinite values skipped; a value outside `range` lands in the end bin. Empty when there is no span.
    public static func bins(values: [Float], count: Int = 64, range: ClosedRange<Float>? = nil) -> [Int] {
        let finite = values.filter(\.isFinite)
        guard count > 0, let lo = range?.lowerBound ?? finite.min(), let hi = range?.upperBound ?? finite.max(), hi > lo else { return [] }
        var out = [Int](repeating: 0, count: count)
        let k = Float(count) / (hi - lo)
        for v in finite { out[min(max(Int((v - lo) * k), 0), count - 1)] += 1 }
        return out
    }

    public static func bins(values: [Double], count: Int = 64, range: ClosedRange<Double>? = nil) -> [Int] {
        bins(values: values.map(Float.init), count: count, range: range.map { Float($0.lowerBound)...Float($0.upperBound) })
    }

    /// The extremes and the mean of the finite values; nil when there are none.
    public static func statistics(of values: [Float]) -> HistogramStatistics? {
        let finite = values.filter(\.isFinite)
        guard let lo = finite.min(), let hi = finite.max() else { return nil }
        return HistogramStatistics(minimum: lo, maximum: hi, mean: finite.reduce(0, +) / Float(finite.count))
    }
}

/// The histogram section of the popover: the bins over the map's range, the footer's statistics, the section's title and the value a bin of 1.0 stands for.
public struct MapDisplayHistogram: Sendable, Equatable {
    public var counts: [Int]
    public var statistics: HistogramStatistics
    public var title: String
    public var scale: Float

    public init(counts: [Int], statistics: HistogramStatistics, title: String, scale: Float = 1) {
        self.counts = counts; self.statistics = statistics; self.title = title; self.scale = scale
    }
}

public struct MapDisplayPopover: View {
    public enum Kind {
        case element(color: Binding<RegionColor>)
        case reference(colormap: Binding<ColormapKind>)
        case mix(items: [MapColorItem], isIn: (String) -> Bool, toggle: (String) -> Void)
    }

    private let kind: Kind
    private let histogram: MapDisplayHistogram?
    private let low: Binding<Double>
    private let high: Binding<Double>
    private let gamma: Binding<Double>
    private let reset: (() -> Void)?
    @Environment(\.self) private var environment

    /// `low`, `high`, `gamma`: the map's `MapAdjustment` fields (the window as fractions of the histogram's range). `reset`: what Reset Range does (nil: the full range).
    public init(kind: Kind, histogram: MapDisplayHistogram?,
                low: Binding<Double>, high: Binding<Double>, gamma: Binding<Double>, reset: (() -> Void)? = nil) {
        self.kind = kind; self.histogram = histogram; self.low = low; self.high = high; self.gamma = gamma; self.reset = reset
    }

    public var body: some View {
        Form {
            Section {
                switch kind {
                case .element(let color):
                    ColorPicker("Colour", selection: Binding(get: { color.wrappedValue.color }, set: { color.wrappedValue = RegionColor($0, resolvedIn: environment) }), supportsOpacity: false)
                        .accessibilityIdentifier("maps.color")
                case .reference(let colormap):
                    Picker("Colormap", selection: colormap) {
                        ForEach(ColormapKind.allCases) { kind in
                            Label { Text(kind.displayName) } icon: { Colormaps.swatch(kind).clipShape(RoundedRectangle(cornerRadius: 2)) }.tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("maps.colormap")
                case .mix(let items, let isIn, let toggle):
                    ForEach(items) { item in
                        Toggle(item.title, isOn: Binding(get: { isIn(item.id) }, set: { _ in toggle(item.id) }))
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("maps.mix.\(item.id)")
                    }
                }
            } header: {
                if case .mix = kind { Text("Maps in the colour mix") }
            }
            if let histogram {
                Section(histogram.title) {
                    HistogramChart(counts: histogram.counts, statistics: histogram.statistics,
                                   rangeLo: Binding(get: { Float(low.wrappedValue) }, set: { low.wrappedValue = Double($0) }),
                                   rangeHi: Binding(get: { Float(high.wrappedValue) }, set: { high.wrappedValue = Double($0) }),
                                   scale: histogram.scale, reset: reset)
                        .help("Drag the handles to set this map's contrast window.")
                    AdjustmentSlider("Gamma", value: gamma, in: 0.2...3, defaultValue: 1)
                }
            }
        }
    }
}
