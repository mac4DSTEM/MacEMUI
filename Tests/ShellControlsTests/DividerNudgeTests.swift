// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEMTests/DividerNudgeTests.swift lines 1-47 (macTEM@51c944c macTEMTests/DividerNudgeTests.swift folded in: nothing; macTEM kept only the process-strip tests)
// Changes: `@testable import ShellControls`; class nonisolated. SPLIT: `testStripTallerOpensAndGrows` and `testStripShorterClosesAtTheFloorAndStaysShut` test `DividerNudge.processFraction`, which is in ShellLayout; they go to Tests/ShellLayoutTests/DividerNudgeProcessTests.swift. Assertions identical.
// END MOVED FROM
//
//  DividerNudgeTests.swift
//  UI audit 2026-10-14, G4: the two dividers (the science panes' and the status strip) move from the keyboard and
//  from VoiceOver by the same arithmetic. Pure functions; the views only call them.
//
//  Mutations these were broken against (each must turn a test red):
//   1. `paneFraction` drops the clamp                                            -> testPaneNudgeStaysInsideTheFloor
//

import XCTest
@testable import ShellControls

nonisolated final class DividerNudgeTests: XCTestCase {


    func testPaneNudgeMovesByTheStepAndStaysInsideTheFloor() {
        let usable: CGFloat = 1000, smallest: CGFloat = 0.2
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.5, by: DividerNudge.step, usable: usable, smallest: smallest),
                       0.5 + DividerNudge.step / usable, accuracy: 1e-9)
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.5, by: -DividerNudge.step, usable: usable, smallest: smallest),
                       0.5 - DividerNudge.step / usable, accuracy: 1e-9)
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.8, by: 1000, usable: usable, smallest: smallest), 0.8,
                       accuracy: 1e-9, "the trailing pane keeps its floor")
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.2, by: -1000, usable: usable, smallest: smallest), 0.2,
                       accuracy: 1e-9, "the leading pane keeps its floor")
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.05, by: 0, usable: usable, smallest: smallest), 0.2,
                       accuracy: 1e-9, "a stored fraction outside the floor is brought inside it")
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.5, by: 24, usable: 0, smallest: smallest), 0.5,
                       "no width, no move")
    }

    func testPaneNudgeStaysInsideTheFloor() {
        // Many presses never leave [smallest, 1 - smallest].
        var fraction: CGFloat = 0.5
        for _ in 0..<200 {
            fraction = DividerNudge.paneFraction(from: fraction, by: DividerNudge.step, usable: 600, smallest: 0.3)
        }
        XCTAssertEqual(fraction, 0.7, accuracy: 1e-9)
    }
}
