// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEMTests/DividerNudgeTests.swift lines 48-86 (macTEM@51c944c macTEMTests/DividerNudgeTests.swift folded in: nothing; same two tests)
// Changes: the process-strip half of DividerNudgeTests; belongs with `DividerNudge.processFraction` in ShellLayout. `@testable import ShellLayout`; class nonisolated; assertions identical.
// END MOVED FROM
// Drop into Tests/ShellLayoutTests/DividerNudgeProcessTests.swift.
import ShellControls
import XCTest
@testable import ShellLayout

nonisolated final class DividerNudgeProcessTests: XCTestCase {

    @MainActor func testStripTallerOpensAShutAreaToWhereItWasAndGrowsAnOpenOne() {
        let available: CGFloat = 800
        let last = LayoutPolicy.processAreaIdealFraction
        XCTAssertEqual(DividerNudge.processFraction(from: 0, taller: true, last: last, available: available), last,
                       "a shut area opens to where it was last open")
        let open = 0.3
        let taller = DividerNudge.processFraction(from: open, taller: true, last: last, available: available)
        XCTAssertGreaterThan(taller, open, "taller grows the area")
        XCTAssertEqual(taller, Double((CGFloat(open) * available + DividerNudge.step) / available), accuracy: 1e-9)
    }

    @MainActor func testStripShorterClosesAtTheFloorAndStaysShut() throws {
        let available: CGFloat = 800
        let last = LayoutPolicy.processAreaIdealFraction
        let open = 0.3
        let shorter = DividerNudge.processFraction(from: open, taller: false, last: last, available: available)
        XCTAssertLessThan(shorter, open)
        XCTAssertGreaterThan(shorter, 0)
        // Held down it shrinks to the floor (140 pt), the next press closes it, and a further press leaves it shut.
        var fraction = open
        var floorHeight: CGFloat?
        for _ in 0..<100 {
            fraction = DividerNudge.processFraction(from: fraction, taller: false, last: last, available: available)
            if fraction > 0 { floorHeight = ProcessAreaLayout.height(fraction: fraction, available: available) }
        }
        XCTAssertEqual(fraction, 0, "a mouse closes it by dragging past the floor; the keyboard closes it from the floor")
        XCTAssertEqual(try XCTUnwrap(floorHeight), LayoutPolicy.processAreaMinimumHeight, accuracy: 0.001,
                       "the last open height is the floor")
        XCTAssertEqual(DividerNudge.processFraction(from: 0, taller: false, last: last, available: available), 0)
        // And held up, it ends at the column's full height, no more.
        var up = open
        for _ in 0..<200 { up = DividerNudge.processFraction(from: up, taller: true, last: last, available: available) }
        XCTAssertEqual(up, 1, accuracy: 1e-9)
    }
}
