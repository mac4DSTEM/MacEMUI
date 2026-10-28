import CoreGraphics
import XCTest
@testable import ShellLayout

nonisolated final class LayoutPolicyTests: XCTestCase {

    // MARK: - The window's width budget

    func testInfobarDragReachesBothExtremesWithoutMovingTheFixedBarHeight() {
        let available: CGFloat = 600
        let hidden = ProcessAreaLayout.heights(fraction: 0, available: available)
        XCTAssertEqual(hidden.canvas, available)
        XCTAssertEqual(hidden.process, 0)

        let full = ProcessAreaLayout.heights(fraction: 1, available: available)
        XCTAssertEqual(full.canvas, 0)
        XCTAssertEqual(full.process, available)

        let draggedUp = ProcessAreaLayout.fraction(afterDrag: -300, available: available, from: 0.25)
        XCTAssertEqual(draggedUp, 0.75, accuracy: 0.001)
        let draggedDown = ProcessAreaLayout.fraction(afterDrag: 300, available: available, from: 0.25)
        XCTAssertEqual(draggedDown, 0, accuracy: 0.001)
    }

    /// `WindowAnatomyPolicy` is retired (2026-09-22): the window's own
    /// minimum width now HAS to cover the ideal columns plus both science
    /// panes at their floor, so nothing collapses a panel to make room
    /// anymore. Pins the derivation itself, the 915 it gives (macTEM's pin), and that it stays comfortably
    /// above the 640 pt the old, too-narrow constant used.
    func testDatasetWindowMinimumWidthCoversTheIdealColumnsAndBothSciencePanes() {
        let required = LayoutPolicy.sidebarWidth.ideal + LayoutPolicy.inspectorWidth.ideal
            + LayoutPolicy.splitColumnDividerAllowance * 2 + LayoutPolicy.scienceMinimum
        XCTAssertGreaterThanOrEqual(LayoutPolicy.datasetWindowMinimumSize.width, required)
        XCTAssertEqual(LayoutPolicy.datasetWindowMinimumSize.width, 915)
        XCTAssertGreaterThanOrEqual(LayoutPolicy.datasetWindowMinimumSize.width, 900)
    }

    /// The sidebar dragged to its maximum must still leave the inspector and
    /// both science panes their floor at the window's minimum. A saved sidebar
    /// wider than that crashed every launch in the constraint loop at 915 pt
    /// (restored window − sidebar ≤ 639 pt crashed, ≥ 640
    /// launched; the 320-pt maximum was inside the crash region).
    func testTheWidestSidebarStillFitsTheMinimumWindow() {
        let required = LayoutPolicy.sidebarWidth.max + LayoutPolicy.inspectorWidth.min
            + LayoutPolicy.splitColumnDividerAllowance * 2 + LayoutPolicy.scienceMinimum
        XCTAssertLessThanOrEqual(required, LayoutPolicy.datasetWindowMinimumSize.width)
    }

    /// The sidebar's step-aside line (1095 pt with the inspector shown) is what the window-width probe test
    /// reads in the apps: 915 < 1095.
    func testTheSidebarStepsAsideBelowTheLine() {
        XCTAssertFalse(LayoutPolicy.navigatorFits(windowWidth: 915, inspectorVisible: true))
        XCTAssertEqual(LayoutPolicy.navigatorLine(inspectorVisible: true), 1095)
        XCTAssertTrue(LayoutPolicy.navigatorFits(windowWidth: 1095, inspectorVisible: true))
    }

    // MARK: - ProcessAreaLayout: the floor

    /// A sliver the owner reached by dragging (or that a scene stored) draws at the floor, 140 pt.
    /// 836 pt is the usable column at 1470 × 923 (map.json P6b). Above the floor nothing changes.
    /// Mutation: drop `max(share, LayoutPolicy.processAreaMinimumHeight)` in `ProcessAreaLayout.height` -> process 41.8.
    func testAnOpenAreaIsNeverDrawnUnderTheFloor() {
        let usable: CGFloat = 836
        let sliver = ProcessAreaLayout.heights(fraction: 0.05, available: usable)
        XCTAssertEqual(sliver.process, 140, "0.05 × 836 = 41.8 pt would be a header-only sliver")
        XCTAssertEqual(sliver.canvas, usable - 140)
        let tiny = ProcessAreaLayout.heights(fraction: 0.0001, available: usable)
        XCTAssertEqual(tiny.process, 140)

        let ideal = ProcessAreaLayout.heights(fraction: LayoutPolicy.processAreaIdealFraction, available: usable)
        XCTAssertEqual(ideal.process, usable * CGFloat(LayoutPolicy.processAreaIdealFraction), accuracy: 0.001,
                       "above the floor the fraction is exact")
    }

    /// The owner's two extremes survive: 0 hides the area, 1 hides the canvas; a column shorter than the floor
    /// gives the area all of it (as fraction 1 does) and never a negative canvas; a fraction outside 0…1 (no
    /// clamp inside `height` any more) is read by the guard and the cap: below 0 hides, above 1 is the column.
    /// Mutation: drop the `min(…, usable)` cap in `ProcessAreaLayout.height` -> process 140 > the 100-pt column
    /// (and 900 > the 600-pt column at fraction 1.5); `guard share > 0` -> `guard fraction != 0` -> fraction -0.5 draws 140.
    func testTheExtremesAndAShortColumnStayInsideTheColumn() {
        let hidden = ProcessAreaLayout.heights(fraction: 0, available: 600)
        XCTAssertEqual(hidden.process, 0)
        XCTAssertEqual(hidden.canvas, 600)
        let full = ProcessAreaLayout.heights(fraction: 1, available: 600)
        XCTAssertEqual(full.process, 600)
        XCTAssertEqual(full.canvas, 0)
        let over = ProcessAreaLayout.heights(fraction: 1.5, available: 600)
        XCTAssertEqual(over.process, 600, "a fraction over 1 is the whole column")
        XCTAssertEqual(over.canvas, 0)
        let under = ProcessAreaLayout.heights(fraction: -0.5, available: 600)
        XCTAssertEqual(under.process, 0, "a negative fraction hides the area")
        XCTAssertEqual(under.canvas, 600)

        let short = ProcessAreaLayout.heights(fraction: 0.5, available: 100)
        XCTAssertEqual(short.process, 100, "the floor never exceeds the column")
        XCTAssertEqual(short.canvas, 0)
        let none = ProcessAreaLayout.heights(fraction: 0.5, available: 0)
        XCTAssertEqual(none.process, 0)
        XCTAssertEqual(none.canvas, 0)
    }

    // MARK: - ProcessAreaLayout: the drag

    /// A drag below 70 pt closes the area (the bottom edge still hides it); 70 pt and up holds.
    /// 800 pt column, start 0.25 = 200 pt exactly, so 130 pt of downward travel is exactly 70 pt.
    /// Mutation: delete the `proposed < processAreaSnapShutHeight` line in `fraction(afterDrag:)` -> 69 pt holds at the floor.
    func testADragBelowSeventyPointsClosesTheArea() {
        let usable: CGFloat = 800
        let floorFraction = 140.0 / 800.0
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 131, available: usable, from: 0.25), 0,
                       "69 pt closes")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 130, available: usable, from: 0.25), floorFraction,
                       accuracy: 1e-9, "exactly 70 pt holds at the floor")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 600, available: usable, from: 0.25), 0,
                       "dragged to the bottom edge, as before")

        // From closed, an upward drag opens the area only once it has travelled 70 pt, and then at the floor.
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: -69, available: usable, from: 0), 0)
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: -71, available: usable, from: 0), floorFraction,
                       accuracy: 1e-9)
    }

    /// Between the snap and the floor the area holds at the floor; above it follows the pointer; the top edge hides the canvas.
    /// Mutation: drop `max(proposed, LayoutPolicy.processAreaMinimumHeight)` in `fraction(afterDrag:)` -> 100/800 = 0.125.
    func testADragBetweenTheSnapAndTheFloorHoldsAtTheFloor() {
        let usable: CGFloat = 800
        let floorFraction = 140.0 / 800.0
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 100, available: usable, from: 0.25), floorFraction,
                       accuracy: 1e-9, "100 pt proposed holds at 140")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 60, available: usable, from: 0.25), floorFraction,
                       accuracy: 1e-9, "exactly 140 pt")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: -100, available: usable, from: 0.25), 0.375,
                       accuracy: 1e-9, "above the floor it follows the pointer: 300 pt")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: -2000, available: usable, from: 0.25), 1,
                       "the top edge hides the canvas")
    }

    /// Grabbing a stored sliver starts from what is on screen (the floor), not from the sliver's own height:
    /// no jump on the first pixel, and a 50-pt drag down from the 140-pt area holds instead of closing.
    /// Mutation: start `fraction(afterDrag:)` from `start * available` (the raw stored height) -> 0.05 × 800 = 40 pt closes.
    func testGrabbingAStoredSliverStartsFromTheFloor() {
        let usable: CGFloat = 800
        let floorFraction = 140.0 / 800.0
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 0.5, available: usable, from: 0.05), floorFraction,
                       accuracy: 1e-9, "the first pixel of travel does not move the bar")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 50, available: usable, from: 0.05), floorFraction,
                       accuracy: 1e-9, "140 − 50 = 90 pt holds at the floor")
        XCTAssertEqual(ProcessAreaLayout.fraction(afterDrag: 80, available: usable, from: 0.05), 0,
                       "140 − 80 = 60 pt closes")
    }

    /// The owner's numbers, and that the floor leaves the science panes (header + 180 pt) their minimum at the
    /// window's own minimum height, so a column cannot be too short for it in the app: 640 − 34 − 140 = 466 pt
    /// of canvas, with 52 pt for the title bar and toolbar and 100 pt of margin still to spare.
    /// Mutation: raise `processAreaMinimumHeight` to 440 -> the canvas beside it falls under a pane's minimum.
    func testTheFloorIsTheOwnersNumbersAndFitsBesideTheCanvasAtTheWindowMinimum() {
        XCTAssertEqual(LayoutPolicy.processAreaMinimumHeight, 140)
        XCTAssertEqual(LayoutPolicy.processAreaSnapShutHeight, 70)
        let canvas = LayoutPolicy.datasetWindowMinimumSize.height - LayoutPolicy.statusStripHeight
            - LayoutPolicy.processAreaMinimumHeight
        XCTAssertGreaterThanOrEqual(canvas, LayoutPolicy.imagePaneMinimum + LayoutPolicy.paneHeaderHeight + 52 + 100)
    }
}
