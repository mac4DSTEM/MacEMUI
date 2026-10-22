import SwiftUI
import XCTest
@testable import ShellSpectroscopy
import ShellControls

nonisolated final class MapTilesTests: XCTestCase {
    /// The grid reflows to the size: at the same width a smaller tile fits more per row, and one tile always fits.
    func testTheGridReflowsToTheTileSize() {
        XCTAssertEqual(MapTileSize.small.columns(in: 740), 4)
        XCTAssertEqual(MapTileSize.medium.columns(in: 740), 3)
        XCTAssertEqual(MapTileSize.large.columns(in: 740), 2)
        XCTAssertEqual(MapTileSize.large.columns(in: 100), 1, "a narrow block still shows one tile")
        XCTAssertLessThan(MapTileSize.small.widths.max, MapTileSize.medium.widths.min + 100)
        XCTAssertEqual(MapTileSize.allCases.map(\.title), ["Small", "Medium", "Large"])
    }

    /// Each pane keeps its floor while there is room for two; below two floors the split halves.
    func testTheSplitKeepsBothFloors() {
        let wide = VerticalPaneSplit<EmptyView, EmptyView>.bounds(usable: 800, minimumTop: 160, minimumBottom: 200)
        XCTAssertEqual(wide.smallest, 0.2, accuracy: 1e-12)
        XCTAssertEqual(wide.largest, 0.75, accuracy: 1e-12)
        let tight = VerticalPaneSplit<EmptyView, EmptyView>.bounds(usable: 300, minimumTop: 160, minimumBottom: 200)
        XCTAssertEqual(tight.smallest, 0.5); XCTAssertEqual(tight.largest, 0.5)
    }
}

nonisolated final class FittedTileLayoutTests: XCTestCase {
    /// One square tile fills the shorter side; four fit two by two in a square; a wide space puts tiles in a row; the tiles never overflow the container.
    func testTheLargestTilesThatFit() {
        let one = FittedTileLayout.best(count: 1, aspect: 1, in: CGSize(width: 400, height: 300))
        XCTAssertEqual(one.columns, 1); XCTAssertEqual(one.tile.width, 300); XCTAssertEqual(one.tile.height, 300)
        let four = FittedTileLayout.best(count: 4, aspect: 1, in: CGSize(width: 408, height: 408), spacing: 8)
        XCTAssertEqual(four.columns, 2); XCTAssertEqual(four.tile.width, 200)
        let row = FittedTileLayout.best(count: 4, aspect: 1, in: CGSize(width: 1000, height: 200), spacing: 8)
        XCTAssertEqual(row.columns, 4, "a wide short space is one row"); XCTAssertLessThanOrEqual(row.tile.height, 200)
        for (count, size) in [(3, CGSize(width: 500, height: 700)), (7, CGSize(width: 640, height: 360)), (5, CGSize(width: 300, height: 900))] {
            let l = FittedTileLayout.best(count: count, aspect: 1.5, in: size, spacing: 8)
            let rows = (count + l.columns - 1) / l.columns
            XCTAssertLessThanOrEqual(CGFloat(l.columns) * l.tile.width + CGFloat(l.columns - 1) * 8, size.width + 0.5, "\(count) tiles in \(size)")
            XCTAssertLessThanOrEqual(CGFloat(rows) * l.tile.height + CGFloat(rows - 1) * 8, size.height + 0.5)
            XCTAssertEqual(l.tile.width / l.tile.height, 1.5, accuracy: 0.02, "the picture keeps its aspect")
        }
    }

    /// A very tall scan (215 x 926) gets narrow tiles in a column that fits the height; an empty space or no tiles give a zero layout.
    func testATallScanAndTheEmptyCases() {
        let tall = FittedTileLayout.best(count: 3, aspect: 215.0 / 926.0, in: CGSize(width: 600, height: 500), spacing: 8)
        XCTAssertEqual(tall.columns, 3); XCTAssertLessThanOrEqual(tall.tile.height, 500)
        XCTAssertEqual(FittedTileLayout.best(count: 0, aspect: 1, in: CGSize(width: 100, height: 100)).tile, .zero)
        XCTAssertEqual(FittedTileLayout.best(count: 2, aspect: 1, in: .zero).tile, .zero)
        let b = HorizontalPaneSplit<EmptyView, EmptyView>.bounds(usable: 800, minimumLeading: 160, minimumTrailing: 240)
        XCTAssertEqual(b.smallest, 0.2, accuracy: 1e-12); XCTAssertEqual(b.largest, 0.7, accuracy: 1e-12)
    }
}

nonisolated final class MapViewTransformTests: XCTestCase {
    /// Zooming about a point keeps that picture point where it is on the tile; zooming out returns to the fit and the centre; the view never leaves the picture.
    func testZoomAboutThePointer() {
        var t = MapViewTransform()
        let size = CGSize(width: 200, height: 100)
        let anchor = CGPoint(x: 0.25, y: 0.75)
        let before = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)   // where the anchor is on the tile at fit
        t.zoom(by: 4, about: anchor)
        XCTAssertEqual(t.zoom, 4)
        let tilePoint = { (picture: CGPoint) -> CGPoint in
            let p = t.placement(in: size)
            return CGPoint(x: size.width / 2 + p.scale * (picture.x * size.width - size.width / 2) + p.offset.width,
                           y: size.height / 2 + p.scale * (picture.y * size.height - size.height / 2) + p.offset.height)
        }
        XCTAssertEqual(tilePoint(anchor).x, before.x, accuracy: 1e-9); XCTAssertEqual(tilePoint(anchor).y, before.y, accuracy: 1e-9)
        XCTAssertEqual(t.picturePoint(forTile: before, in: size).x, anchor.x, accuracy: 1e-9)
        t.zoom(by: 1.0 / 4, about: anchor)
        XCTAssertEqual(t, MapViewTransform(), "back to the fit and the centre")
        t.zoom(by: 1000, about: CGPoint(x: 0, y: 0))
        XCTAssertEqual(t.zoom, MapViewTransform.maximumZoom)
        XCTAssertGreaterThanOrEqual(t.center.x, 0.5 / 64 - 1e-12); XCTAssertGreaterThanOrEqual(t.center.y, 0.5 / 64 - 1e-12)
        t.zoom(by: 0.001, about: CGPoint(x: 1, y: 1))
        XCTAssertEqual(t.zoom, 1); XCTAssertEqual(t.center, CGPoint(x: 0.5, y: 0.5))
    }

    /// A drag moves the picture with the pointer, stays inside the picture, and does nothing at the fit.
    func testPan() {
        var t = MapViewTransform()
        let size = CGSize(width: 200, height: 200)
        t.pan(by: CGSize(width: 50, height: 0), in: size)
        XCTAssertEqual(t, MapViewTransform(), "nothing to pan at the fit")
        t.zoom(by: 2, about: CGPoint(x: 0.5, y: 0.5))
        t.pan(by: CGSize(width: 40, height: -20), in: size)
        XCTAssertEqual(t.center.x, 0.5 - 40 / (200 * 2), accuracy: 1e-12); XCTAssertEqual(t.center.y, 0.5 + 20 / (200 * 2), accuracy: 1e-12)
        t.pan(by: CGSize(width: 10_000, height: 10_000), in: size)
        XCTAssertEqual(t.center.x, 0.25, accuracy: 1e-12, "the left edge of the picture stops at the tile's edge"); XCTAssertEqual(t.center.y, 0.25, accuracy: 1e-12)
        t.reset()
        XCTAssertTrue(t.isFit)
        XCTAssertGreaterThan(ScrollZoom.factor(delta: 5, isPrecise: false), 1); XCTAssertLessThan(ScrollZoom.factor(delta: -5, isPrecise: true), 1)
        XCTAssertEqual(ScrollZoom.factor(delta: .nan, isPrecise: true), 1)
    }
}
