import XCTest
@testable import ShellSpectroscopy

nonisolated final class SpectrumLayersTests: XCTestCase {
    private func layer(_ counts: [Double], origin: Double = 0, step: Double = 1) -> SpectrumLayer {
        SpectrumLayer(id: "a", name: "A", color: RegionPalette.color(at: 0), origin: origin, step: step, counts: counts)
    }

    /// A narrow peak survives thinning to fewer columns than channels: the column holds the min and the max.
    func testThinningKeepsANarrowPeak() {
        var counts = [Double](repeating: 1, count: 1000)
        counts[437] = 500
        let cols = SpectrumLayerPlot.columns(of: layer(counts), in: 0...999, columns: 100, scale: .linear)
        XCTAssertEqual(cols.count, 100)
        XCTAssertEqual(cols.map(\.high).max(), 500)
        XCTAssertEqual(cols.first { $0.high == 500 }?.low, 1)
        XCTAssertEqual(SpectrumLayerPlot.columns(of: layer([1, 2, 3]), in: 0...2, columns: 100, scale: .linear).count, 3, "fewer channels than columns: one each")
    }

    /// The window selects channels by the axis, and an inverted or empty window gives nothing.
    func testTheWindowSelectsChannelsByTheAxis() {
        let l = layer([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], origin: 10, step: 0.5)   // 10.0 ... 14.5
        let cols = SpectrumLayerPlot.columns(of: l, in: 11...12, columns: 50, scale: .linear)
        XCTAssertEqual(cols.map(\.high), [2, 3, 4])
        XCTAssertEqual(cols.map(\.x), [11, 11.5, 12])
        XCTAssertTrue(SpectrumLayerPlot.columns(of: l, in: 20...30, columns: 10, scale: .linear).isEmpty, "a window off the axis holds nothing")
    }

    /// Log is log10 with a floor of one count; the peak and the shape normalisation read the same window.
    func testScalesPeakAndNormalisation() {
        XCTAssertEqual(SpectrumScale.log.transform(1000), 3, accuracy: 1e-12)
        XCTAssertEqual(SpectrumScale.log.transform(0), 0, "a zero channel sits on the floor")
        XCTAssertEqual(SpectrumScale.linear.transform(7), 7)
        let big = layer([10, 100, 50]), small = layer([1, 5, 2])
        XCTAssertEqual(SpectrumLayerPlot.peak(of: [big, small], in: 0...2, scale: .linear), 100)
        XCTAssertEqual(SpectrumLayerPlot.peak(of: [big, small], in: 0...2, scale: .linear, normalized: true), 1, "each layer scaled to its own maximum")
        XCTAssertEqual(SpectrumLayerPlot.normalizer(of: small, in: 0...1), 5)
        XCTAssertEqual(SpectrumLayerPlot.normalizer(of: layer([0, 0]), in: 0...1), 1, "an empty layer does not divide by zero")
        XCTAssertNil(SpectrumLayerPlot.peak(of: [], in: 0...1, scale: .linear))
    }
}

nonisolated final class ProfileSeriesTests: XCTestCase {
    func testDistancesAndTheSpokenSummary() {
        let s = ProfileSeries(id: "mg", name: "Mg", color: RegionPalette.color(at: 0), values: [1, 4, 2.5], spacing: 0.5)
        XCTAssertEqual(s.distance(of: 2), 1.0)
        XCTAssertEqual(s.length, 1.0)
        XCTAssertEqual(ProfileSeries(id: "e", name: "E", color: RegionPalette.color(at: 0), values: [], spacing: 1).length, 0)
        XCTAssertEqual(ProfileChart.summary([s], unit: "nm"), "Mg: 1 to 4 over 1 nm")
    }
}
