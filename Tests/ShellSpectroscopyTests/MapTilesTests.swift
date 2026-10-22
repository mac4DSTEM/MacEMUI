import SwiftUI
import XCTest
@testable import ShellSpectroscopy

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
