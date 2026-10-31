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

    /// Picking a disabled segment leaves the selection where it was; an enabled one is taken.
    func testPickingADisabledSegmentKeepsTheSelection() {
        let segments: [SegmentedControl.Segment] = [.title("Net"), .title("MLLS", disabledReason: "arrives later"), .symbol(name: "circle", label: "Ellipse")]
        XCTAssertEqual(SegmentedMapping.pick(1, among: segments, current: 0), 0, "a disabled segment is not taken")
        XCTAssertEqual(SegmentedMapping.pick(2, among: segments, current: 0), 2)
        XCTAssertEqual(SegmentedMapping.pick(-1, among: segments, current: 0), -1, "no segment stays no segment")
    }

    /// A segment built with the old cases has no reason and is enabled; the reason is the tooltip after the help.
    func testTheOldInitHasNoReasonAndTheReasonIsTheTooltip() {
        XCTAssertNil(SegmentedControl.Segment.title("Net", help: "Net counts").disabledReason)
        XCTAssertTrue(SegmentedControl.Segment.symbol(name: "circle", label: "Ellipse", help: "Draw").isEnabled)
        XCTAssertEqual(SegmentedControl.Segment.title("Net", help: "Net counts").toolTip, "Net counts")
        XCTAssertNil(SegmentedControl.Segment.title("Net").toolTip)
        let off = SegmentedControl.Segment.title("MLLS", help: "Multiple linear least squares", disabledReason: "the fit arrives with the next slice")
        XCTAssertFalse(off.isEnabled)
        XCTAssertEqual(off.toolTip, "Multiple linear least squares\nOff: the fit arrives with the next slice")
    }

    /// VoiceOver's help for the control names each segment that is off, with its reason; nothing when all are on.
    func testTheSpokenHelpNamesTheSegmentsThatAreOff() {
        XCTAssertNil(SegmentedMapping.offHelp([.title("Net"), .symbol(name: "circle", label: "Ellipse")]))
        XCTAssertEqual(SegmentedMapping.offHelp([.title("Net"), .title("MLLS", disabledReason: "the fit arrives later"),
                                                 .symbol(name: "lasso", label: "Polygon", disabledReason: "no map yet")]),
                       "MLLS off: the fit arrives later. Polygon off: no map yet")
    }

    func testControlSizesMapOneToOne() {
        XCTAssertEqual(SegmentedControl.controlSize(.small), .small)
        XCTAssertEqual(SegmentedControl.controlSize(.large), .large)
    }
}
