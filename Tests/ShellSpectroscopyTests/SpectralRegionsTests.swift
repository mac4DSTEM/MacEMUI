import Foundation
import XCTest
@testable import ShellSpectroscopy

nonisolated final class SpectralRegionsTests: XCTestCase {
    private let box = RegionGeometry.rectangle(x0: 2, y0: 3, x1: 10, y1: 9)

    /// Regions are named by a running count and take the palette in turn; a deleted region's name and colour are not handed on.
    func testRegionsAreNamedAndColouredInTurn() {
        var set = SpectralRegionSet()
        let a = set.add(box), b = set.add(.ellipse(x0: 0, y0: 0, x1: 4, y1: 4)), c = set.add(box)
        XCTAssertEqual(set.regions.map(\.name), ["Region 1", "Region 2", "Region 3"])
        XCTAssertEqual(set.regions.map(\.color), [RegionPalette.color(at: 0), RegionPalette.color(at: 1), RegionPalette.color(at: 2)])
        set.remove(b)
        let d = set.add(box)
        XCTAssertEqual(set.regions.map(\.name), ["Region 1", "Region 3", "Region 4"])
        XCTAssertEqual(set.regions.last?.color, RegionPalette.color(at: 3))
        XCTAssertEqual(set.selectedID, d, "the new region is the selected one")
        XCTAssertEqual(RegionPalette.color(at: RegionPalette.colors.count), RegionPalette.color(at: 0), "the palette cycles")
        XCTAssertNotEqual(a, c)
    }

    /// Lines are named apart and pool no spectrum; selection moves on after a delete and ignores unknown ids.
    func testLinesPoolNothingAndSelectionFollows() {
        var set = SpectralRegionSet()
        let region = set.add(box)
        let line = set.add(.line(RegionPoint(x: 0, y: 0), RegionPoint(x: 3, y: 4)))
        XCTAssertEqual(set.regions[1].name, "Line 2")
        XCTAssertEqual(set.spectrumRegions.map(\.id), [region])
        XCTAssertEqual(set.regions[1].geometry.lineLength ?? 0, 5, accuracy: 1e-12)
        set.remove(line)
        XCTAssertEqual(set.selectedID, region, "deleting the selected last region selects the one before")
        set.select(UUID())
        XCTAssertEqual(set.selectedID, region, "an id that is not in the set is not selectable")
        set.removeAll()
        XCTAssertNil(set.selectedID)
    }

    /// Rename trims and refuses a blank name; hiding keeps the region in the set but out of `visible`.
    func testRenameAndVisibility() {
        var set = SpectralRegionSet()
        let id = set.add(box)
        set.rename(id, to: "  Grain boundary ")
        XCTAssertEqual(set.regions[0].name, "Grain boundary")
        set.rename(id, to: "   ")
        XCTAssertEqual(set.regions[0].name, "Grain boundary")
        set.setVisible(id, false)
        XCTAssertTrue(set.visible.isEmpty)
        XCTAssertEqual(set.spectrumRegions.count, 1)
        set.setColor(id, RegionColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(set.regions[0].color, RegionColor(red: 1, green: 0, blue: 0))
    }

    /// Bounds and centre of every shape, and the session round trip.
    func testGeometryBoundsAndTheSessionRoundTrip() throws {
        let poly = RegionGeometry.polygon([RegionPoint(x: 1, y: 5), RegionPoint(x: 7, y: 2), RegionPoint(x: 4, y: 9)])
        XCTAssertEqual(poly.bounds.x0, 1); XCTAssertEqual(poly.bounds.y1, 9)
        XCTAssertEqual(poly.centre, RegionPoint(x: 4, y: 5.5))
        XCTAssertEqual(RegionGeometry.rectangle(x0: 10, y0: 9, x1: 2, y1: 3).bounds.x0, 2, "a dragged-backwards box is normalised")
        var set = SpectralRegionSet()
        set.add(box); set.add(poly); set.add(.line(RegionPoint(x: 0, y: 0), RegionPoint(x: 1, y: 1)))
        let back = try JSONDecoder().decode(SpectralRegionSet.self, from: JSONEncoder().encode(set))
        XCTAssertEqual(back, set)
    }
}

nonisolated final class SpectralRegionSetRebuildTests: XCTestCase {
    /// An app can rebuild a set from its own regions; an unknown selection is dropped.
    func testASetRebuiltFromRegionsKeepsThemAndDropsAnUnknownSelection() {
        let r = SpectralRegion(name: "Grain", color: RegionPalette.color(at: 4), geometry: .rectangle(x0: 0, y0: 0, x1: 1, y1: 1))
        var set = SpectralRegionSet(regions: [r], selectedID: r.id)
        XCTAssertEqual(set.selectedID, r.id)
        XCTAssertNil(SpectralRegionSet(regions: [r], selectedID: UUID()).selectedID)
        set.add(.rectangle(x0: 0, y0: 0, x1: 2, y1: 2))
        XCTAssertEqual(set.regions.last?.name, "Region 2", "numbering continues after the rebuilt regions")
    }
}

nonisolated final class RegionDrawingTests: XCTestCase {
    private let size = CGSize(width: 160, height: 80)   // a 16 x 8 scan at 10 points per pixel

    /// A point maps to the pixel under it, clamped to the last; off the picture is nil.
    func testPixelsUnderPoints() {
        XCTAssertEqual(RegionDrawing.pixel(at: CGPoint(x: 5, y: 5), in: size, scanWidth: 16, scanHeight: 8)?.x, 0)
        let last = RegionDrawing.pixel(at: CGPoint(x: 160, y: 80), in: size, scanWidth: 16, scanHeight: 8)
        XCTAssertEqual(last?.x, 15); XCTAssertEqual(last?.y, 7)
        XCTAssertNil(RegionDrawing.pixel(at: CGPoint(x: -1, y: 5), in: size, scanWidth: 16, scanHeight: 8))
    }

    /// Two corners span the pixels under both, in either order; a drag past the edge is clamped to it.
    func testASpannedBoxIncludesBothCornerPixels() throws {
        let a = try XCTUnwrap(RegionDrawing.spannedBox(from: CGPoint(x: 25, y: 12), to: CGPoint(x: 64, y: 47), in: size, scanWidth: 16, scanHeight: 8))
        XCTAssertEqual([a.x0, a.y0, a.x1, a.y1], [2, 1, 7, 5])
        let b = try XCTUnwrap(RegionDrawing.spannedBox(from: CGPoint(x: 64, y: 47), to: CGPoint(x: 25, y: 12), in: size, scanWidth: 16, scanHeight: 8))
        XCTAssertEqual([b.x0, b.y0, b.x1, b.y1], [2, 1, 7, 5], "the same box dragged backwards")
        let c = try XCTUnwrap(RegionDrawing.spannedBox(from: CGPoint(x: 150, y: 70), to: CGPoint(x: 400, y: 300), in: size, scanWidth: 16, scanHeight: 8))
        XCTAssertEqual([c.x0, c.y0, c.x1, c.y1], [15, 7, 16, 8], "clamped to the picture")
    }

    /// Scan points are continuous (pixel i covers [i, i+1)); a polygon closes only with three vertices and a click near the first.
    func testScanPointsAndPolygonClosing() {
        let p = RegionDrawing.scanPoint(CGPoint(x: 85, y: 20), in: size, scanWidth: 16, scanHeight: 8)
        XCTAssertEqual(p.x, 8.5, accuracy: 1e-12); XCTAssertEqual(p.y, 2, accuracy: 1e-12)
        let v = [RegionPoint(x: 1, y: 1), RegionPoint(x: 5, y: 1), RegionPoint(x: 3, y: 4)]
        XCTAssertTrue(RegionDrawing.closesPolygon(v, click: CGPoint(x: 12, y: 8), in: size, scanWidth: 16, scanHeight: 8, radius: 9))
        XCTAssertFalse(RegionDrawing.closesPolygon(v, click: CGPoint(x: 60, y: 8), in: size, scanWidth: 16, scanHeight: 8, radius: 9))
        XCTAssertFalse(RegionDrawing.closesPolygon(Array(v.prefix(2)), click: CGPoint(x: 12, y: 8), in: size, scanWidth: 16, scanHeight: 8, radius: 9), "two vertices are not a polygon")
        XCTAssertEqual(RegionTool.allCases.map(\.title), ["Rectangle", "Ellipse", "Polygon", "Line"])
    }
}

nonisolated final class RegionEditingTests: XCTestCase {
    private let box = RegionGeometry.rectangle(x0: 2, y0: 3, x1: 6, y1: 7)

    /// A box has eight handles, a polygon one per vertex, a line two.
    func testHandles() {
        XCTAssertEqual(RegionEditing.handles(of: box).count, 8)
        XCTAssertEqual(RegionEditing.handles(of: .polygon([RegionPoint(x: 0, y: 0), RegionPoint(x: 4, y: 0), RegionPoint(x: 2, y: 3)])).count, 3)
        XCTAssertEqual(RegionEditing.handles(of: .line(RegionPoint(x: 0, y: 0), RegionPoint(x: 5, y: 5))).count, 2)
    }

    /// A press on a handle resizes, inside moves, outside is nothing; a line is hit within the tolerance and a closed shape by its inside.
    func testHits() {
        // 10 points per pixel
        XCTAssertEqual(RegionEditing.hit(box, at: CGPoint(x: 21, y: 31), sx: 10, sy: 10, radius: 8), .handle(.box(x: -1, y: -1)))
        XCTAssertEqual(RegionEditing.hit(box, at: CGPoint(x: 60, y: 50), sx: 10, sy: 10, radius: 8), .handle(.box(x: 1, y: 0)))
        XCTAssertEqual(RegionEditing.hit(box, at: CGPoint(x: 40, y: 50), sx: 10, sy: 10, radius: 8), .body)
        XCTAssertNil(RegionEditing.hit(box, at: CGPoint(x: 150, y: 150), sx: 10, sy: 10, radius: 8))
        let circle = RegionGeometry.ellipse(x0: 0, y0: 0, x1: 10, y1: 10)
        XCTAssertTrue(RegionEditing.contains(circle, RegionPoint(x: 5, y: 5), tolerance: 0))
        XCTAssertFalse(RegionEditing.contains(circle, RegionPoint(x: 0.5, y: 0.5), tolerance: 0), "a corner of the box is outside the ellipse")
        let line = RegionGeometry.line(RegionPoint(x: 0, y: 0), RegionPoint(x: 10, y: 0))
        XCTAssertTrue(RegionEditing.contains(line, RegionPoint(x: 5, y: 0.5), tolerance: 0.8))
        XCTAssertFalse(RegionEditing.contains(line, RegionPoint(x: 5, y: 2), tolerance: 0.8))
        let tri = RegionGeometry.polygon([RegionPoint(x: 0, y: 0), RegionPoint(x: 8, y: 0), RegionPoint(x: 4, y: 6)])
        XCTAssertTrue(RegionEditing.contains(tri, RegionPoint(x: 4, y: 2), tolerance: 0))
        XCTAssertFalse(RegionEditing.contains(tri, RegionPoint(x: 0.5, y: 5), tolerance: 0))
    }

    /// Moving keeps the shape inside the grid by shifting back, and boxes move in whole pixels.
    func testMovingStaysInsideTheGrid() {
        XCTAssertEqual(RegionEditing.moved(box, dx: 1.4, dy: -1.6, scanWidth: 16, scanHeight: 16), .rectangle(x0: 3, y0: 1, x1: 7, y1: 5))
        XCTAssertEqual(RegionEditing.moved(box, dx: 100, dy: 100, scanWidth: 16, scanHeight: 16), .rectangle(x0: 12, y0: 12, x1: 16, y1: 16))
        XCTAssertEqual(RegionEditing.moved(box, dx: -100, dy: 0, scanWidth: 16, scanHeight: 16), .rectangle(x0: 0, y0: 3, x1: 4, y1: 7))
        let poly = RegionGeometry.polygon([RegionPoint(x: 1, y: 1), RegionPoint(x: 3, y: 1), RegionPoint(x: 2, y: 3)])
        XCTAssertEqual(RegionEditing.moved(poly, dx: 0.25, dy: 0, scanWidth: 8, scanHeight: 8), .polygon([RegionPoint(x: 1.25, y: 1), RegionPoint(x: 3.25, y: 1), RegionPoint(x: 2.25, y: 3)]), "a polygon moves continuously")
    }

    /// A corner moves two edges to whole pixels, an edge one; a box never closes below a pixel; vertices follow the point inside the grid.
    func testResizing() {
        XCTAssertEqual(RegionEditing.resized(box, handle: .box(x: 1, y: 1), to: RegionPoint(x: 8.4, y: 9.6), scanWidth: 16, scanHeight: 16), .rectangle(x0: 2, y0: 3, x1: 8, y1: 10))
        XCTAssertEqual(RegionEditing.resized(box, handle: .box(x: -1, y: 0), to: RegionPoint(x: 0.2, y: 99), scanWidth: 16, scanHeight: 16), .rectangle(x0: 0, y0: 3, x1: 6, y1: 7), "an edge leaves the other axis alone")
        XCTAssertEqual(RegionEditing.resized(box, handle: .box(x: 1, y: 0), to: RegionPoint(x: -5, y: 0), scanWidth: 16, scanHeight: 16), .rectangle(x0: 2, y0: 3, x1: 3, y1: 7), "at least one pixel")
        let circle = RegionGeometry.ellipse(x0: 0, y0: 0, x1: 4, y1: 4)
        XCTAssertEqual(RegionEditing.resized(circle, handle: .box(x: 1, y: 1), to: RegionPoint(x: 9, y: 9), scanWidth: 16, scanHeight: 16), .ellipse(x0: 0, y0: 0, x1: 9, y1: 9))
        let line = RegionGeometry.line(RegionPoint(x: 0, y: 0), RegionPoint(x: 5, y: 5))
        XCTAssertEqual(RegionEditing.resized(line, handle: .vertex(1), to: RegionPoint(x: 99, y: 3.5), scanWidth: 8, scanHeight: 8), .line(RegionPoint(x: 0, y: 0), RegionPoint(x: 8, y: 3.5)))
    }
}
