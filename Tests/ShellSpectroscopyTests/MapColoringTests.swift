import ShellControls
import XCTest
import ShellMetal
@testable import ShellSpectroscopy

nonisolated final class MapColoringTests: XCTestCase {
    private let red = RegionColor(red: 1, green: 0, blue: 0)
    private let green = RegionColor(red: 0, green: 1, blue: 0)

    private func pixel(_ rgba: [UInt8], _ i: Int) -> [UInt8] { Array(rgba[4 * i..<4 * i + 4]) }

    /// A colour map is black at zero, the colour at the largest value and linear between; a map with no positive pixel is black.
    func testAColourMapRunsFromBlackToTheColour() {
        let rgba = MapRaster.rgba(values: [0, 5, 10], coloring: .color(red))
        XCTAssertEqual(pixel(rgba, 0), [0, 0, 0, 255])
        XCTAssertEqual(pixel(rgba, 1), [128, 0, 0, 255])
        XCTAssertEqual(pixel(rgba, 2), [255, 0, 0, 255])
        XCTAssertEqual(pixel(MapRaster.rgba(values: [-1, 0], coloring: .color(red)), 0), [0, 0, 0, 255])
        XCTAssertEqual(pixel(MapRaster.rgba(values: [0, 5, 10], coloring: .color(red), upper: 5), 2), [255, 0, 0, 255], "values above the given scale clamp")
    }

    /// A colormap map reads the shared LUT at the value's fraction; NaN is hatched when the width is given, and black without it.
    func testAColormapMapReadsTheSharedLUTAndHatchesNaN() {
        let lut = Colormaps.lutRGBA(.viridis)
        let rgba = MapRaster.rgba(values: [0, 10], coloring: .colormap(.viridis))
        let end = Colormaps.sampleRGB(lut, 1), start = Colormaps.sampleRGB(lut, 0)
        XCTAssertEqual(pixel(rgba, 1), [end.0, end.1, end.2, 255])
        XCTAssertEqual(pixel(rgba, 0), [start.0, start.1, start.2, 255])
        let hatched = MapRaster.rgba(values: [.nan, .nan, .nan, .nan, .nan, .nan, 1], coloring: .color(red), width: 7)
        XCTAssertEqual(Set(hatched[0..<4].dropLast()), [120], "grey stripes where the kit had no value")
        XCTAssertEqual(pixel(MapRaster.rgba(values: [.nan, 1], coloring: .color(red)), 0), [0, 0, 0, 255])
    }

    /// The mix adds each map's fraction times its colour and clamps; each map is scaled by its own maximum.
    func testTheMixAddsMapsEachInItsOwnColour() {
        let layers = [MapRaster.MixLayer(values: [0, 1, 2], color: red), MapRaster.MixLayer(values: [0, 100, 0], color: green)]
        let rgba = MapRaster.mix(layers, count: 3)
        XCTAssertEqual(pixel(rgba, 0), [0, 0, 0, 255])
        XCTAssertEqual(pixel(rgba, 1), [128, 255, 0, 255], "half red plus full green")
        XCTAssertEqual(pixel(rgba, 2), [255, 0, 0, 255])
        let both = MapRaster.mix([MapRaster.MixLayer(values: [1], color: red), MapRaster.MixLayer(values: [1], color: RegionColor(red: 1, green: 1, blue: 0))], count: 1)
        XCTAssertEqual(pixel(both, 0), [255, 255, 0, 255], "channels clamp at full")
    }

    /// The appearance keeps the person's choices, falls back to the default, resets, and survives a session round trip with a chosen mix.
    func testTheAppearanceKeepsChoicesAndRoundTrips() throws {
        var a = MapAppearance()
        XCTAssertEqual(a.coloring(for: "Mg", default: .color(red)), .color(red))
        a.set(.colormap(.inferno), for: "Mg")
        XCTAssertEqual(a.coloring(for: "Mg", default: .color(red)), .colormap(.inferno))
        a.set(nil, for: "Mg")
        XCTAssertEqual(a.coloring(for: "Mg", default: .color(red)), .color(red))
        a.set(.color(green), for: "Al")
        XCTAssertEqual(a.mix.selection(among: ["Mg", "Al"]), ["Mg", "Al"], "the default mix holds every map")
        a.mix.toggle("Al", among: ["Mg", "Al"])
        XCTAssertEqual(a.mix.members, ["Mg"])
        let back = try JSONDecoder().decode(MapAppearance.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back, a)
        a.reset()
        XCTAssertEqual(a, MapAppearance())
        XCTAssertEqual(MapColoring.colormap(.gray).endColor.red, 1, accuracy: 0.02)
    }
}

nonisolated final class MapAdjustmentTests: XCTestCase {
    /// The window clamps below `low` and above `high`, the gamma bends the middle, the default changes nothing, and a default adjustment is not kept.
    func testTheWindowAndTheGamma() {
        let a = MapAdjustment(low: 0.2, high: 0.6, gamma: 1)
        XCTAssertEqual(a.apply(0.1), 0); XCTAssertEqual(a.apply(0.7), 1)
        XCTAssertEqual(a.apply(0.4), 0.5, accuracy: 1e-12)
        XCTAssertEqual(MapAdjustment(gamma: 2).apply(0.25), 0.5, accuracy: 1e-12, "gamma above 1 brightens the middle")
        XCTAssertEqual(MapAdjustment().apply(0.37), 0.37)
        var appearance = MapAppearance()
        appearance.setAdjustment(a, for: "Mg")
        XCTAssertEqual(appearance.adjustment(for: "Mg"), a)
        appearance.setAdjustment(MapAdjustment(), for: "Mg")
        XCTAssertTrue(appearance.adjustments.isEmpty)
        appearance.setAdjustment(a, for: "Al"); appearance.reset()
        XCTAssertTrue(appearance.adjustments.isEmpty, "reset clears the adjustments too")
    }

    /// The pixels follow the adjustment: a half-scale value under a 0.5...1 window is black.
    func testThePixelsFollowTheAdjustment() throws {
        let c = RegionColor(red: 1, green: 0, blue: 0)
        let plain = MapRaster.rgba(values: [5, 10], coloring: .color(c))
        let windowed = MapRaster.rgba(values: [5, 10], coloring: .color(c), adjustment: MapAdjustment(low: 0.5, high: 1))
        XCTAssertEqual(plain[0], 128); XCTAssertEqual(windowed[0], 0); XCTAssertEqual(windowed[4], 255)
        let mixed = MapRaster.mix([MapRaster.MixLayer(values: [5, 10], color: c, adjustment: MapAdjustment(low: 0.5, high: 1))], count: 2)
        XCTAssertEqual(mixed[0], 0); XCTAssertEqual(mixed[4], 255)
        let old = try JSONDecoder().decode(MapAppearance.self, from: Data(#"{"colorings":{},"mix":{"isOn":false,"members":[]}}"#.utf8))
        XCTAssertEqual(old, MapAppearance(), "an appearance saved before adjustments existed still reads")
    }
}

nonisolated final class PeriodicTableGridTests: XCTestCase {
    /// 118 symbols, the table's rows hold each element of periods 1 to 6 once (the f-block and period 7 are folded), and the sizes follow the width.
    func testTheTableIsComplete() {
        XCTAssertEqual(PeriodicTableGrid.symbols.count, 118)
        XCTAssertEqual(PeriodicTableGrid.symbol(1), "H"); XCTAssertEqual(PeriodicTableGrid.symbol(28), "Ni"); XCTAssertEqual(PeriodicTableGrid.symbol(78), "Pt"); XCTAssertEqual(PeriodicTableGrid.symbol(118), "Og")
        XCTAssertEqual(PeriodicTableGrid.symbol(0), ""); XCTAssertEqual(PeriodicTableGrid.symbol(119), "")
        let shown = PeriodicTableGrid.rows.joined().compactMap { $0 }
        XCTAssertEqual(Set(shown).union(PeriodicTableGrid.folded), Set(1...118), "every element is in the table or the fold")
        XCTAssertEqual(shown.count + PeriodicTableGrid.folded.count, 118, "none twice")
        XCTAssertTrue(PeriodicTableGrid.rows.allSatisfy { $0.count == 18 })
        XCTAssertEqual(PeriodicTableGrid.cellSize(width: 248), (248 - 17 * 2) / 18, accuracy: 1e-12)
        XCTAssertEqual(PeriodicTableGrid.symbolSize(cell: 40), 13); XCTAssertEqual(PeriodicTableGrid.symbolSize(cell: 10), 9)
        XCTAssertEqual(PeriodicTable.describe(.fitOnly), "fit only")
        XCTAssertEqual(ElementRoleChoice.allCases.map(\.title), ["Quantify", "Fit only", "Off"])
    }
}


nonisolated final class ColorMixSelectionTests: XCTestCase {
    private let all = ["O", "Ni", "Ge"]

    /// By default every map is in; a click takes one out (naming the others first), clicks can take every map out (an empty mix), and once all are in again the choice is the default.
    /// Red under: the first click on the default leaving only the clicked map; an empty mix read as "every map".
    func testTheSelectionStatesAreDefinedCleanly() {
        var mix = ColorMix()
        XCTAssertEqual(mix.selection(among: all), all); XCTAssertFalse(mix.isCustom)
        mix.toggle("Ni", among: all)
        XCTAssertEqual(mix.selection(among: all), ["O", "Ge"]); XCTAssertTrue(mix.isCustom)
        XCTAssertFalse(mix.contains("Ni", among: all)); XCTAssertTrue(mix.contains("O", among: all))
        mix.toggle("O", among: all); mix.toggle("Ge", among: all)
        XCTAssertEqual(mix.selection(among: all), [], "every map taken out: an empty mix, not every map")
        XCTAssertTrue(mix.isCustom)
        mix.toggle("Ge", among: all)
        XCTAssertEqual(mix.selection(among: all), ["Ge"])
        mix.toggle("Ni", among: all); mix.toggle("O", among: all)
        XCTAssertEqual(mix.selection(among: all), all, "all in again: in the list's order")
        XCTAssertFalse(mix.isCustom, "and the choice is the default again")
    }

    /// The order of the mix follows the maps' order, not the order of the clicks; an id that is no map is ignored; an old saved mix still reads.
    func testOrderAndCompatibility() throws {
        var mix = ColorMix()
        mix.toggle("Ge", among: all); mix.toggle("Ni", among: all); mix.toggle("O", among: all)   // out, out, out
        mix.toggle("Ni", among: all); mix.toggle("O", among: all)
        XCTAssertEqual(mix.selection(among: all), ["O", "Ni"])
        XCTAssertEqual(mix.selection(among: ["O"]), ["O"], "a map that is gone is not selected")
        let old = try JSONDecoder().decode(ColorMix.self, from: Data(#"{"isOn":true,"members":["A","B"]}"#.utf8))
        XCTAssertTrue(old.isCustom); XCTAssertEqual(old.members, ["A", "B"])
        let fresh = try JSONDecoder().decode(ColorMix.self, from: Data(#"{"isOn":true,"members":[]}"#.utf8))
        XCTAssertFalse(fresh.isCustom)
        let saved = try XCTUnwrap(String(data: JSONEncoder().encode(old), encoding: .utf8))
        XCTAssertFalse(saved.contains("isOn"), "the old on/off flag is read past and not written again")
    }
}

nonisolated final class MapHistogramTests: XCTestCase {
    /// 64 bins over the finite range: NaN and infinities are skipped, the largest value lands in the last bin, the total is the finite count.
    func testBinsCoverTheFiniteRangeAndSkipNaN() {
        let values: [Float] = [0, 1, 2, 3, 4, 5, 6, 7, .nan, .infinity]
        let bins = MapHistogram.bins(values: values)
        XCTAssertEqual(bins.count, 64)
        XCTAssertEqual(bins.reduce(0, +), 8)
        XCTAssertEqual(bins.first, 1); XCTAssertEqual(bins.last, 1)
        XCTAssertEqual(MapHistogram.bins(values: [Float](repeating: 2, count: 5)), [], "no span, no bars")
        XCTAssertEqual(MapHistogram.bins(values: [Double]([0, 5]), count: 4, range: 0...10), [1, 0, 1, 0], "an explicit range")
        XCTAssertEqual(MapHistogram.statistics(of: [1, 3, .nan])?.mean, 2)
    }
}
