//
//  EDXRoomTests.swift
//  The shared EDX room's pure rules and its call sites: the number strings, the spectrum window's arithmetic, the map pixels,
//  the periodic table's places, the maps block's layout. Each fix is right in its pure function while reverting the line that
//  uses it leaves every pure test green; the source checks go red when that line reverts. How an app mounts the room is that
//  app's own test.
//

import ShellLayout
import XCTest
import UniformTypeIdentifiers
import SpectroCore
import SpectroEDX
@testable import ShellEDXModel
@testable import ShellSpectroscopy

nonisolated final class EDXRoomTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    // MARK: The verb is the toolbar's (design 2026-10-22, §2.2)

    func testTheHeaderStatusIsSecondaryTextNeverAControl() {
        XCTAssertNil(EDXRoomFormat.statusText(quantified: false, hasPicks: false))
        XCTAssertEqual(EDXRoomFormat.statusText(quantified: false, hasPicks: true), "Identified")
        XCTAssertEqual(EDXRoomFormat.statusText(quantified: true, hasPicks: true), "Quantified · live ✓")
    }

    /// Quantify is the room's one verb, in the app's toolbar; the header holds no button for it or for Stop. Red under: the header's
    /// Quantify or Stop button back in `EDXRoom.swift`.
    func testQuantifyAndStopLeaveTheHeader() throws {
        let room = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXRoom.swift"))
        XCTAssertFalse(room.contains("Button(session.quantifyActive"))
        XCTAssertFalse(room.contains("Button(\"Stop\""))
    }

    // MARK: The maps block (ShellSpectroscopy)

    /// The maps and the spectrum are separated by MacEMUI's `VerticalPaneSplit` (stored, nudgeable) and the tiles are the anchored grid of `MapTileView`s.
    /// Red under: a fixed 40 % height back; the grid back to a `LazyVGrid`.
    func testTheMapsBlockIsTheSharedSplitAndAnchoredGrid() throws {
        let room = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXRoom.swift"))
        XCTAssertTrue(room.contains("VerticalPaneSplit(storageKey: \"edx.lowerSplit\""))
        XCTAssertFalse(room.contains("lowerPaneFraction"))
        XCTAssertFalse(room.contains("EDXHeader"), "no strip of controls above the maps")
        let block = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXMapsBlock.swift"))
        XCTAssertTrue(block.contains("AnchoredMapsBlock(anchor: composition.anchor"))
        XCTAssertTrue(block.contains("MapTileView("))
        XCTAssertTrue(block.contains("regions: isAnchor ? regions : nil"), "regions are drawn and shown on the anchor tile only")
        XCTAssertFalse(block.contains("LazyVGrid"))
        XCTAssertFalse(block.contains("EDXMapsStatus"), "no banner over the maps: the status line is the inspector's")

        let inspector = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXRoomInspector.swift"))
        XCTAssertTrue(inspector.contains("InspectorSection(\"Maps\")")); XCTAssertTrue(inspector.contains("InspectorSection(\"Tools\")"))
        XCTAssertFalse(inspector.contains("InspectorSection(\"View\")")); XCTAssertFalse(inspector.contains("InspectorSection(\"Regions\")"))
        XCTAssertFalse(inspector.contains("Compare shape"))

        // The standard's controls: MacEMUI's full-width segmented control for the quantity and the region tool, the Filter row under it.
        XCTAssertTrue(inspector.contains("SegmentedPicker(label: \"Maps\""));  XCTAssertTrue(inspector.contains("accessibilityIdentifier(\"edx.mapMode\")"))
        XCTAssertTrue(inspector.contains("SegmentedPicker(label: \"Region tool\"")); XCTAssertTrue(inspector.contains("accessibilityIdentifier(\"edx.tool\")"))
        XCTAssertFalse(inspector.contains(".pickerStyle(.segmented)"), "a segmented Picker keeps its intrinsic width")
        XCTAssertTrue(inspector.contains("InspectorRow(\"Filter\")")); XCTAssertTrue(inspector.contains("$state.mapFilter"))

        // The zoom is read in the body, before the GeometryReader, so a drag redraws continuously.
        let spectrum = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXSpectrumView.swift"))
        let read = try XCTUnwrap(spectrum.range(of: "let yZoom = state.yZoom")), reader = try XCTUnwrap(spectrum.range(of: "GeometryReader {"))
        XCTAssertLessThan(read.lowerBound, reader.lowerBound)

        for file in ["Sources/ShellSpectroscopy/EDX/EDXMapsBlock.swift", "Sources/ShellSpectroscopy/EDX/EDXRoom.swift", "Sources/ShellSpectroscopy/EDX/EDXRoomInspector.swift", "Sources/ShellSpectroscopy/EDX/EDXSpectrumView.swift", "Sources/ShellSpectroscopy/EDX/EDXRoomState.swift"] {
            XCTAssertFalse(try source(file).contains("mix.isOn"), "the colour mix is always the anchor: \(file)")
        }
    }

    /// The maps start in the elements' own colours (distinct per element, black to the colour) and the scan image in grey; a new file resets the choice.
    /// A tile carries no chip and no hover colour scale (the status line has the value); its popover is MacEMUI's display popover; the display filter is
    /// applied to composition tiles only (never the net maps, never the HAADF) and a filtered tile says so. Red under: the chip or the old sliders back; the
    /// filter applied to every tile; the tag dropped.
    @MainActor func testTheTileHasNoChipAndTheFilterIsForCompositionTilesOnly() throws {
        let block = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXMapsBlock.swift"))
        XCTAssertTrue(block.contains("MapDisplayPopover("))
        XCTAssertFalse(block.contains("MapColorControls")); XCTAssertFalse(block.contains("startExpanded")); XCTAssertFalse(block.contains("colorbar:"))
        XCTAssertFalse(block.contains("valueText: spec.valueText"), "the value is the status line's")
        XCTAssertTrue(block.contains("tile.mode == .net ? .off : chosen"), "net maps are never filtered")
        XCTAssertTrue(block.contains("filteredTag: spec.filtered"))
        XCTAssertFalse(block.contains("width: width, adjustment"), "no hatching on a composition tile")
        XCTAssertEqual(EDXRoomState().mapFilter, .mean3x3, "the 3 × 3 average is the default")
        let tile = squeezed(try source("Sources/ShellSpectroscopy/MapTileView.swift"))
        XCTAssertFalse(tile.contains("maps.hoverChip")); XCTAssertFalse(tile.contains("MapColorbarView(spec: colorbar)"))
        XCTAssertTrue(tile.contains("maps.filteredTag"))
    }

    @MainActor func testTheMapsStartInTheElementsOwnColours() {
        XCTAssertEqual(EDXRoomState().appearance, MapAppearance())
        XCTAssertNotEqual(EDXRegionBridge.defaultColoring("Mg"), EDXRegionBridge.defaultColoring("Al"))
        XCTAssertEqual(EDXRegionBridge.defaultColoring("Mg"), EDXRegionBridge.defaultColoring("Mg"))
        if case .color = EDXRegionBridge.defaultColoring("Si") {} else { XCTFail("an element map runs from black to its colour") }
        let room = squeezed((try? source("Sources/ShellSpectroscopy/EDX/EDXRoom.swift")) ?? "")
        XCTAssertTrue(room.contains("state.appearance = MapAppearance()"), "a new file starts from the defaults")
    }

    @MainActor func testTheRoomStatesStartWithNothingSolo() {
        XCTAssertNil(EDXRoomState().soloTile)
    }

    /// Esc goes back to the arrow tool from any drawing tool; with the arrow already chosen it does nothing and says so.
    @MainActor func testEscapeReturnsToTheArrowTool() throws {
        let state = EDXRoomState()
        XCTAssertFalse(state.escape(), "nothing to leave")
        for tool in RegionTool.allCases where tool != .pointer {
            state.tool = tool
            XCTAssertTrue(state.escape())
            XCTAssertEqual(state.tool, .pointer)
        }
        let room = try source("Sources/ShellSpectroscopy/EDX/EDXRoom.swift")
        let squeezedRoom = squeezed(room)
        XCTAssertTrue(squeezedRoom.contains("Button(\"Arrow Tool\") { state.escape() } .keyboardShortcut(.cancelAction) .disabled(state.tool == .pointer)"),
                      "the room routes Esc to it, whatever holds the focus, only while a drawing tool is chosen")
    }

    // MARK: Fit to

    /// A Fit to entry at or below 0.2 keV is refused in words and the default kept; zero is the default without a note; above it is the range's end.
    /// The inspector shows the refusal under the field. Red under: the field resetting silently (no refusal, or the note not shown).
    func testAFitToBelowTheMinimumIsRefusedInWords() throws {
        let posix = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(EDXRoomFormat.fitTo(entered: 8, locale: posix).keV, 8)
        XCTAssertNil(EDXRoomFormat.fitTo(entered: 8, locale: posix).refusal)
        XCTAssertNil(EDXRoomFormat.fitTo(entered: 0, locale: posix).keV)
        XCTAssertNil(EDXRoomFormat.fitTo(entered: 0, locale: posix).refusal, "an emptied field is the default, said nowhere")
        for v in [0.1, 0.2, -5] {
            XCTAssertNil(EDXRoomFormat.fitTo(entered: v, locale: posix).keV)
            XCTAssertEqual(EDXRoomFormat.fitTo(entered: v, locale: posix).refusal, "Fit to must be above 0.2 keV: the default range is used.")
        }
        let inspector = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXRoomInspector.swift"))
        XCTAssertTrue(inspector.contains("let entry = EDXRoomFormat.fitTo(entered: v) fitToRefusal = entry.refusal session.changeMethod { $0.fitToKeV = entry.keV }"))
        XCTAssertTrue(inspector.contains("if let fitToRefusal { InspectorNote(fitToRefusal)"))
    }

    // MARK: Strings

    func testCountsGroupByThousandsWithAThinSpace() {
        XCTAssertEqual(EDXRoomFormat.counts(0), "0")
        XCTAssertEqual(EDXRoomFormat.counts(999), "999")
        XCTAssertEqual(EDXRoomFormat.counts(1234), "1\u{2009}234")
        XCTAssertEqual(EDXRoomFormat.counts(1_234_567.4), "1\u{2009}234\u{2009}567")
        XCTAssertEqual(EDXRoomFormat.counts(-1500), "−1\u{2009}500")
        XCTAssertEqual(EDXRoomFormat.counts(.nan), "–")
    }

    func testAValueTakesTheDigitsOfItsSigma() {
        XCTAssertEqual(EDXRoomFormat.plusMinus(12.34, 0.56, locale: Locale(identifier: "en_US")), "12.34 \u{00B1} 0.56", "σ to two significant digits")
        XCTAssertEqual(EDXRoomFormat.plusMinus(97.6, 0.05, locale: Locale(identifier: "en_US")), "97.600 \u{00B1} 0.050")
        XCTAssertEqual(EDXRoomFormat.plusMinus(5.5, 12, locale: Locale(identifier: "en_US")), "6 \u{00B1} 12", "no decimals past the unit")
        XCTAssertEqual(EDXRoomFormat.plusMinus(1_000_000, 4000, locale: Locale(identifier: "en_US")), "1000000 \u{00B1} 4000")
        XCTAssertEqual(EDXRoomFormat.plusMinus(3.14159, 0, locale: Locale(identifier: "en_US")), "3.14", "no sigma: two places")
        XCTAssertEqual(EDXRoomFormat.plusMinus(.nan, 1, locale: Locale(identifier: "en_US")), "–")
    }

    func testTheRegionSentenceNamesItsPixels() {
        XCTAssertEqual(EDXRoomFormat.region(.wholeMap, pixels: 12_000), "Whole map · 12\u{2009}000 px")
        XCTAssertEqual(EDXRoomFormat.region(.rectangle(PixelRect(x0: 10, y0: 5, x1: 41, y1: 31)), pixels: 806),
                       "Region · x 10–40, y 5–30 · 806 px")
        XCTAssertEqual(EDXRoomFormat.spectrumSubtitle(counts: 1500, region: .wholeMap, pixels: 4), "1\u{2009}500 counts · Whole map · 4 px")
    }

    func testARegionIsKeyedByItsPixels() {
        XCTAssertEqual(EDXRegion.wholeMap.cacheKey, "whole")
        XCTAssertNotEqual(EDXRegion.rectangle(PixelRect(x0: 0, y0: 0, x1: 2, y1: 2)).cacheKey, EDXRegion.rectangle(PixelRect(x0: 0, y0: 0, x1: 2, y1: 3)).cacheKey)
        XCTAssertEqual(EDXRegion.wholeMap.pixelCount(nx: 5, ny: 4), 20)
        XCTAssertEqual(EDXRegion.rectangle(PixelRect(x0: 1, y0: 1, x1: 3, y1: 4)).pixelCount(nx: 5, ny: 4), 6)
        XCTAssertNil(EDXRegion.wholeMap.mask(nx: 5, ny: 4), "nil: every pixel, the kit's convention")
    }

    // MARK: The spectrum window

    private func plot(counts: [Double], start: Double = 0, step: Double = 0.01) -> EDXPlot { EDXPlot(energyStart: start, energyStep: step, data: counts) }

    /// With marked lines the window runs a little past the highest; without, to where 99.5 % of the counts lie; never under 2 keV.
    func testTheAutomaticWindow() {
        let p = plot(counts: [Double](repeating: 1, count: 2000))   // 0...20 keV
        let marker = EDXMarker(symbol: "Cu", label: "Cu Kα", energy: 8.04, quantified: true)
        XCTAssertEqual(EDXRoomFormat.autoWindow(plot: p, markers: [marker]), 0...(8.04 * 1.25 + 0.5))
        XCTAssertEqual(EDXRoomFormat.autoWindow(plot: p, markers: []).upperBound, 19.9, accuracy: 0.011, "flat counts: 99.5 % lie below 19.9")
        var lowCounts = [Double](repeating: 0, count: 2000); lowCounts[50] = 100
        XCTAssertEqual(EDXRoomFormat.autoWindow(plot: plot(counts: lowCounts), markers: []).upperBound, 2, "never narrower than 2 keV")
        XCTAssertEqual(EDXRoomFormat.autoWindow(plot: plot(counts: [Double](repeating: 1, count: 100)), markers: []).upperBound, 1, accuracy: 1e-9,
                       "nor wider than the axis")
        XCTAssertEqual(EDXRoomFormat.autoWindow(plot: plot(counts: []), markers: []), 0...20)
    }

    /// Zoom and pan stay inside the data and never go under two channels; a zoom keeps the point under the pointer.
    /// Where a drag on the spectrum starts decides what it does (Paul's drive, 2026-10-23): under the plot it zooms the energy axis, left of it the
    /// counts axis, inside it pans. Up on the counts axis zooms in, by the same law as before, never below 1 or above 1000.
    func testASpectrumDragIsAssignedByWhereItStarts() {
        let size = CGSize(width: 600, height: 300)
        XCTAssertEqual(EDXSpectrumDrag.zone(start: CGPoint(x: 300, y: 290), size: size), .energyAxis)
        XCTAssertEqual(EDXSpectrumDrag.zone(start: CGPoint(x: 20, y: 150), size: size), .countsAxis)
        XCTAssertEqual(EDXSpectrumDrag.zone(start: CGPoint(x: 300, y: 150), size: size), .plot)
        XCTAssertEqual(EDXSpectrumDrag.zone(start: CGPoint(x: 20, y: 290), size: size), .energyAxis, "the corner belongs to the energy axis")
        XCTAssertEqual(EDXSpectrumDrag.yZoom(start: 1, dy: -150), exp(1), accuracy: 1e-12)
        XCTAssertEqual(EDXSpectrumDrag.yZoom(start: 1, dy: 150), 1, "never below 1")
        XCTAssertEqual(EDXSpectrumDrag.yZoom(start: 900, dy: -1500), 1000, "never above 1000")
    }

    func testZoomAndPanStayInsideTheData() {
        let domain = 0.0...20.0
        let w = 2.0...8.0
        let zoomed = EDXSpectrumWindow.zoomed(w, factor: 2, anchor: 0.5, domain: domain, minimumSpan: 0.02)
        XCTAssertEqual(zoomed.lowerBound, 3.5, accuracy: 1e-12); XCTAssertEqual(zoomed.upperBound, 6.5, accuracy: 1e-12)
        let anchored = EDXSpectrumWindow.zoomed(w, factor: 2, anchor: 0, domain: domain, minimumSpan: 0.02)
        XCTAssertEqual(anchored.lowerBound, 2, accuracy: 1e-12, "the left edge stays under a pointer at the left edge")
        XCTAssertEqual(EDXSpectrumWindow.zoomed(w, factor: 1e9, anchor: 0.5, domain: domain, minimumSpan: 0.02).upperBound
                       - EDXSpectrumWindow.zoomed(w, factor: 1e9, anchor: 0.5, domain: domain, minimumSpan: 0.02).lowerBound, 0.02, accuracy: 1e-12)
        XCTAssertEqual(EDXSpectrumWindow.zoomed(w, factor: 1e-9, anchor: 0.5, domain: domain, minimumSpan: 0.02), domain, "zoomed out: the whole range")
        XCTAssertEqual(EDXSpectrumWindow.zoomed(w, factor: .nan, anchor: 0.5, domain: domain, minimumSpan: 0.02), w)
        XCTAssertEqual(EDXSpectrumWindow.panned(w, byFraction: 0.5, domain: domain, minimumSpan: 0.02), 5.0...11.0)
        XCTAssertEqual(EDXSpectrumWindow.panned(w, byFraction: -9, domain: domain, minimumSpan: 0.02), 0.0...6.0, "stops at the low end")
        XCTAssertEqual(EDXSpectrumWindow.panned(w, byFraction: 9, domain: domain, minimumSpan: 0.02), 14.0...20.0, "stops at the high end")
    }

    func testTicksAreRoundNumbersInsideTheWindow() {
        XCTAssertEqual(EDXSpectrumWindow.ticks(in: 0...20), [0, 5, 10, 15, 20])
        XCTAssertEqual(EDXSpectrumWindow.ticks(in: 1.3...2.1).first ?? 0, 1.4, accuracy: 1e-9)
        for t in EDXSpectrumWindow.ticks(in: 0.7...9.3) { XCTAssertTrue((0.7...9.3).contains(t)) }
        XCTAssertTrue(EDXSpectrumWindow.ticks(in: 3...3).isEmpty)
    }

    // MARK: Map pixels

    /// A map is black at 0 and the full colour at its maximum; a negative pixel, a NaN and an all-zero map are black.
    func testAMapIsBlackAtZeroAndFullAtItsMaximum() {
        let px = EDXMapRaster.rgba(values: [0, 5, 10, -3, .nan], hue: 0)   // hue 0: red
        XCTAssertEqual(px.count, 20)
        XCTAssertEqual(Array(px[0..<4]), [0, 0, 0, 255])
        XCTAssertEqual(px[8], 255, "the maximum: full red"); XCTAssertEqual(px[9], UInt8((255 * 0.15).rounded())); XCTAssertEqual(px[10], UInt8((255 * 0.15).rounded()))
        XCTAssertEqual(px[4], UInt8((255 * 0.5).rounded()), "half the maximum: half the value")
        XCTAssertEqual(Array(px[12..<16]), [0, 0, 0, 255], "negative: black")
        XCTAssertEqual(Array(px[16..<20]), [0, 0, 0, 255], "NaN: black")
        XCTAssertEqual(Array(EDXMapRaster.rgba(values: [0, 0], hue: 0.3).prefix(4)), [0, 0, 0, 255])
    }

    func testAMapMakesAnImageOnlyWhenItsSizeIsRight() {
        XCTAssertNotNil(EDXMapRaster.cgImage(rgba: [UInt8](repeating: 255, count: 24), width: 3, height: 2))
        XCTAssertNil(EDXMapRaster.cgImage(rgba: [UInt8](repeating: 255, count: 20), width: 3, height: 2))
        XCTAssertNil(EDXMapRaster.cgImage(rgba: [], width: 0, height: 0))
    }

    func testAPointOnAMapIsAPixelInsideTheGrid() {
        let size = CGSize(width: 200, height: 100)
        XCTAssertEqual(EDXMapRaster.pixel(at: CGPoint(x: 0, y: 0), in: size, nx: 4, ny: 2)?.x, 0)
        let corner = EDXMapRaster.pixel(at: CGPoint(x: 200, y: 100), in: size, nx: 4, ny: 2)
        XCTAssertEqual(corner?.x, 3); XCTAssertEqual(corner?.y, 1)
        let middle = EDXMapRaster.pixel(at: CGPoint(x: 101, y: 51), in: size, nx: 4, ny: 2)
        XCTAssertEqual(middle?.x, 2); XCTAssertEqual(middle?.y, 1)
        XCTAssertNil(EDXMapRaster.pixel(at: CGPoint(x: -1, y: 5), in: size, nx: 4, ny: 2))
        XCTAssertNil(EDXMapRaster.pixel(at: CGPoint(x: 5, y: 5), in: .zero, nx: 4, ny: 2))
    }

    func testEachElementHasItsOwnHueAndTheSameOneEveryTime() {
        XCTAssertEqual(EDXRoomFormat.hue(symbol: "Al"), EDXRoomFormat.hue(symbol: "Al"))
        XCTAssertNotEqual(EDXRoomFormat.hue(symbol: "Al"), EDXRoomFormat.hue(symbol: "Si"))
        for s in EDXElements.symbols { XCTAssertTrue((0..<1).contains(EDXRoomFormat.hue(symbol: s)), s) }
    }

    // MARK: The periodic table


    // MARK: The shell's slots

    /// What is selected on the right is what the colour mix shows (the scan image included); nothing selected leaves the anchor empty (its placeholder shows). Red under: the old
    /// semantics, where an empty list meant every map and the scan image could not be selected.
    @MainActor func testClickingMapsMakesCustomMixes() {
        var a = MapAppearance()
        let scan: [Float] = [1, 2]
        let tiles = ["O", "Ni"].map { EDXMapTile(symbol: $0, width: 2, height: 1, values: [1, 2], version: 1, line: "\($0) Kα", note: nil) }
        let all = EDXMapsComposition.selectable(scan: scan, tiles: tiles)
        XCTAssertEqual(all, ["haadf", "O", "Ni"])
        func members() -> [String] {
            if case .mix(let m)? = EDXMapsComposition.items(scan: scan, tiles: tiles, appearance: a).anchor?.kind { return m.map(\.id) }
            XCTFail("the colour mix is the anchor"); return []
        }
        XCTAssertEqual(members(), ["O", "Ni"], "the elements are in, the scan image only when clicked")
        EDXMapsComposition.toggle("haadf", in: &a.mix, scan: scan, tiles: tiles)
        XCTAssertEqual(members(), all)
        EDXMapsComposition.toggle("haadf", in: &a.mix, scan: scan, tiles: tiles)
        EDXMapsComposition.toggle("O", in: &a.mix, scan: scan, tiles: tiles); EDXMapsComposition.toggle("Ni", in: &a.mix, scan: scan, tiles: tiles)
        XCTAssertEqual(members(), [], "nothing selected: the anchor stays, empty")
        EDXMapsComposition.toggle("haadf", in: &a.mix, scan: scan, tiles: tiles)
        XCTAssertEqual(members(), ["haadf"])
    }

    /// The room's element symbols are MacEMUI's table's, in atomic order.
    func testTheRoomAndTheTableAgreeOnTheElements() {
        XCTAssertEqual(EDXElements.symbols, PeriodicTableGrid.symbols)
        XCTAssertEqual(EDXElements.symbols.count, 118)
        XCTAssertEqual(EDXElements.symbol(z: 26), "Fe"); XCTAssertEqual(EDXElements.z(of: "Fe"), 26); XCTAssertNil(EDXElements.z(of: "Xx"))
    }

    /// The right-click menu's lines: an element's families with their lines and energies, alpha first, the default family selected until one is chosen, a checked line marked. Red under:
    /// every family offered for a light element; the choice not read back.
    func testTheLineMenuListsFamiliesAndLines() throws {
        let fe = EDXElements.lineFamilies(symbol: "Fe", pick: nil, energy: { String(format: "%.3f", $0) })
        XCTAssertEqual(fe.map(\.family), [.K, .L], "iron has K and L lines in the table")
        XCTAssertTrue(fe[0].isSelected); XCTAssertFalse(fe[1].isSelected)
        let kAlpha = try XCTUnwrap(fe[0].lines.first)
        XCTAssertTrue(kAlpha.title.hasPrefix("Kα") && kAlpha.title.hasSuffix("6.404 keV"), kAlpha.title)
        XCTAssertFalse(fe.flatMap(\.lines).contains { $0.isChecked })
        let chosen = EDXPick(symbol: "Fe", role: .quantify, manual: true, family: .L, lines: [fe[1].lines[0].id])
        let after = EDXElements.lineFamilies(symbol: "Fe", pick: chosen)
        XCTAssertTrue(after[1].isSelected); XCTAssertFalse(after[0].isSelected)
        XCTAssertTrue(after[1].lines[0].isChecked)
    }

    /// The table's actions drive the session: a click picks Quantify, Fit only changes the role, Off takes it out, a family and a line are remembered and reset.
    @MainActor func testTheTableActionsDriveTheSession() async {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let actions = EDXPeriodicActions.make(session)
        let ti = 22, h = 1
        func pick() -> EDXPick? { session.picks.first { $0.symbol == "Ti" } }
        XCTAssertEqual(actions.state(ti), .off, "Auto ID does not find titanium in the planted Al-Mg-Si spectrum")
        if case .unavailable = actions.state(h) {} else { XCTFail("hydrogen has no usable line") }
        actions.click(ti)
        XCTAssertEqual(actions.state(ti), .quantify); XCTAssertEqual(actions.role(ti), .quantify)
        actions.setRole(ti, .fitOnly)
        XCTAssertEqual(actions.state(ti), .fitOnly)
        XCTAssertFalse(actions.families(ti).isEmpty)
        actions.setFamily(ti, "L")
        XCTAssertEqual(pick()?.family, .L)
        XCTAssertTrue(actions.hasChosenLines(ti))
        actions.resetLines(ti)
        XCTAssertFalse(actions.hasChosenLines(ti)); XCTAssertNil(pick()?.family)
        actions.setRole(ti, .off)
        XCTAssertEqual(actions.state(ti), .off); XCTAssertNil(pick())
        actions.setRole(ti, .quantify)
        XCTAssertEqual(actions.state(ti), .quantify, "Quantify from Off picks it")
    }

    // MARK: Export kinds

    func testTheExportKindsNameTheirFiles() {
        XCTAssertEqual(EDXExportKind.allCases.map(\.suffix), [" quantification", " method", " spectrum", " spectrum", " pins", " maps", " composition by class"])
        XCTAssertEqual(EDXExportKind.method.contentType, .json)
        XCTAssertEqual(EDXExportKind.results.contentType, .commaSeparatedText)
        XCTAssertEqual(EDXExportKind.spectrum.contentType, .commaSeparatedText)
        XCTAssertEqual(EDXExportKind.pins.contentType, .commaSeparatedText)
        XCTAssertEqual(EDXExportKind.mapsPNG.contentType, .png)
        XCTAssertEqual(EDXExportKind.spectrumMSA.contentType.preferredFilenameExtension, "msa")
        let file = EDXExportFile(data: Data("a,b\n".utf8))
        XCTAssertEqual(String(decoding: file.data, as: UTF8.self), "a,b\n")
    }

    /// Every map mode names its unit for the colorbar.
    func testEveryMapModeNamesItsUnit() {
        XCTAssertEqual(EDXMapMode.allCases.map(\.unit), ["net counts", "wt%", "at%", "kg/m²"])
    }
}
