import SwiftUI
import XCTest
@testable import ShellControls

nonisolated final class SegmentedMappingTests: XCTestCase {
    /// A value finds its segment and a segment its value; a value not among the items has no segment, and no segment is no value.
    func testSelectionAndIndexMapBothWays() {
        let values = ["net", "wt", "at"]
        XCTAssertEqual(SegmentedMapping.index(of: "at", in: values), 2)
        XCTAssertEqual(SegmentedMapping.value(at: 1, in: values), "wt")
        XCTAssertEqual(SegmentedMapping.index(of: "thickness", in: values), -1, "the control shows no selection")
        XCTAssertNil(SegmentedMapping.value(at: -1, in: values))
        XCTAssertNil(SegmentedMapping.value(at: 3, in: values))
    }

    func testControlSizesMapOneToOne() {
        XCTAssertEqual(SegmentedControl.controlSize(.small), .small)
        XCTAssertEqual(SegmentedControl.controlSize(.large), .large)
    }
}
