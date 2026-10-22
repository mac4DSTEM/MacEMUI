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
