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
