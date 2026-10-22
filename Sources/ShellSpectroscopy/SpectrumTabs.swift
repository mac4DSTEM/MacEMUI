//
//  SpectrumTabs.swift
//  Role: the lower block of a spectroscopy room (design 2026-10-22 §2.2): three views of the same regions, picked by a tab row: the spectra overlaid, a profile
//        along a line drawn on a map, and the table of per-region numbers. The room supplies each view; the tab row, the remembered choice and the
//        profile chart are shared.
//

import SwiftUI
import Charts

public nonisolated enum SpectrumPane: String, CaseIterable, Identifiable, Sendable {
    case spectrum, profile, table

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// The tab row: Spectrum, Profile, Table. A pane the room has nothing for (no line drawn, no region) can be left out of `available`.
public struct SpectrumPaneTabs: View {
    @Binding private var selection: SpectrumPane
    private let available: [SpectrumPane]

    public init(selection: Binding<SpectrumPane>, available: [SpectrumPane] = SpectrumPane.allCases) {
        self._selection = selection
        self.available = available
    }

    public var body: some View {
        Picker("View", selection: $selection) {
            ForEach(available) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("spectrum.tabs")
    }
}

/// One profile along a line: a value per sample, `spacing` apart (in `unit`, e.g. nm, or pixels when the scan is uncalibrated).
public nonisolated struct ProfileSeries: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var color: RegionColor
    public var values: [Double]
    public var spacing: Double

    public init(id: String, name: String, color: RegionColor, values: [Double], spacing: Double) {
        self.id = id; self.name = name; self.color = color; self.values = values; self.spacing = spacing
    }

    /// The distance of sample `i` from the line's start.
    public func distance(of i: Int) -> Double { Double(i) * spacing }

    /// The line's length in `spacing` units: the distance of the last sample.
    public var length: Double { values.isEmpty ? 0 : distance(of: values.count - 1) }
}

/// The profile along a line: one coloured line per series (one per element, say), distance on x. `pointerDistance` marks where the pointer is on the map's line.
public struct ProfileChart: View {
    private let series: [ProfileSeries]
    private let unit: String
    private let valueTitle: String
    private let pointerDistance: Double?

    public init(series: [ProfileSeries], unit: String, valueTitle: String = "Value", pointerDistance: Double? = nil) {
        self.series = series
        self.unit = unit
        self.valueTitle = valueTitle
        self.pointerDistance = pointerDistance
    }

    public var body: some View {
        if series.allSatisfy({ $0.values.isEmpty }) {
            ContentUnavailableView("No profile", systemImage: "chart.xyaxis.line",
                                   description: Text("Draw a line on a map to see the profile along it."))
                .accessibilityIdentifier("profile.empty")
        } else {
            Chart {
                ForEach(series) { s in
                    ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("Distance", s.distance(of: i)), y: .value(valueTitle, v), series: .value("Series", s.name))
                            .foregroundStyle(s.color.color)
                            .interpolationMethod(.linear)
                    }
                }
                if let pointerDistance {
                    RuleMark(x: .value("Pointer", pointerDistance)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                }
            }
            .chartXAxisLabel("Distance (\(unit))")
            .chartYAxisLabel(valueTitle)
            .chartLegend(.hidden)
            .accessibilityIdentifier("profile.chart")
            .accessibilityLabel("Profile along the line")
            .accessibilityValue(Self.summary(series, unit: unit))
        }
    }

    /// What VoiceOver reads: each series with its range.
    static func summary(_ series: [ProfileSeries], unit: String) -> String {
        series.compactMap { s in
            guard let lo = s.values.min(), let hi = s.values.max() else { return nil }
            return "\(s.name): \(lo.formatted(.number.precision(.significantDigits(1...3)))) to \(hi.formatted(.number.precision(.significantDigits(1...3)))) over \(s.length.formatted(.number.precision(.significantDigits(1...3)))) \(unit)"
        }.joined(separator: "; ")
    }
}
