// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEMTests/NavigationSeamTests.swift (process-area toggle) and mac4DSTEMTests/FinalPolishFTests.swift (restore and live-snap tests that drive navigation) (macTEM@51c944c macTEMTests/NavigationSeamTests.swift: same toggle test)
// Changes: WorkspaceNavigation -> PanelNavigation, showLogPane -> showProcessArea; new tests for the pane set and the sidebar; the AppState/task/inspector-tab tests of NavigationSeamTests stay in the apps
// END MOVED FROM
import CoreGraphics
import XCTest
@testable import ShellLayout

nonisolated final class PanelNavigationTests: XCTestCase {

    @MainActor func testProcessAreaToggleRestoresTheLastDraggedFraction() {
        let navigation = PanelNavigation()
        navigation.processFraction = 0.6
        navigation.showProcessArea = false
        XCTAssertEqual(navigation.processFraction, 0)
        XCTAssertEqual(navigation.lastProcessFraction, 0.6)
        navigation.showProcessArea = true
        XCTAssertEqual(navigation.processFraction, 0.6)
        XCTAssertEqual(ProcessAreaLayout.toggled(from: 0.6, last: 0.6), 0)
        XCTAssertEqual(ProcessAreaLayout.toggled(from: 0, last: 0.6), 0.6)
    }

    /// Both restore paths: the toggle / ⌃⌘L restore of `lastProcessFraction`, and the scene's saved
    /// `processFraction` (an older version stored slivers). Each is drawn at the floor on every window height,
    /// and the floor also holds when the window shrinks under a fraction that was fine before.
    /// Mutation: drop the floor in `ProcessAreaLayout.height`.
    @MainActor func testARestoredSliverIsNeverDrawnAsOne() {
        let navigation = PanelNavigation()
        navigation.lastProcessFraction = 0.01
        navigation.showProcessArea = true   // the toggle's and ⌃⌘L's restore
        XCTAssertTrue(navigation.showProcessArea, "the area opens")
        for usable in [CGFloat(554), 836, 1100] {
            XCTAssertGreaterThanOrEqual(
                ProcessAreaLayout.heights(fraction: navigation.processFraction, available: usable).process, 140,
                "restored last fraction at \(usable) pt")
        }

        // The infobar's own button restores the same way.
        let viaToggle = ProcessAreaLayout.toggled(from: 0, last: 0.01)
        XCTAssertEqual(ProcessAreaLayout.heights(fraction: viaToggle, available: 836).process, 140)

        // The scene's saved processFraction.
        let saved = PanelNavigation()
        saved.processFraction = 0.05
        XCTAssertEqual(ProcessAreaLayout.heights(fraction: saved.processFraction, available: 836).process, 140)

        // A window that shrinks: 0.2 is 167 pt at 836 but 111 pt at 554 — drawn at the floor.
        XCTAssertEqual(ProcessAreaLayout.heights(fraction: 0.2, available: 836).process, 167.2, accuracy: 0.001)
        XCTAssertEqual(ProcessAreaLayout.heights(fraction: 0.2, available: 554).process, 140)
    }

    /// The snap is LIVE, as the gesture feeds it: the infobar calls `fraction(afterDrag:)` on EVERY drag sample,
    /// from the fraction the drag started at, so the area shuts the moment a sample proposes under 70 pt and comes
    /// back at the floor if the pointer returns before release. `lastProcessFraction` keeps the last OPEN value the
    /// drag passed through, so the toggle and ⌃⌘L reopen at the floor (140 pt), not at the 200 pt the drag started
    /// from. Not a defect: card Q6 a's floor.
    /// Mutation: delete the `proposed < processAreaSnapShutHeight` line in `fraction(afterDrag:)` -> a 60-pt
    /// proposal holds at the floor and the area never closes; or raise the floor to 440 -> the start is drawn at 440.
    @MainActor func testTheSnapIsLiveAndAfterAClosingDragTheToggleReopensAtTheFloor() {
        let usable: CGFloat = 800
        let navigation = PanelNavigation()
        navigation.processFraction = 0.25   // 200 pt: where the drag starts
        let start = navigation.processFraction
        func sample(_ translation: CGFloat) {   // one drag sample, as the infobar feeds it
            navigation.processFraction = ProcessAreaLayout.fraction(afterDrag: translation, available: usable, from: start)
        }
        func drawn() -> CGFloat {
            ProcessAreaLayout.heights(fraction: navigation.processFraction, available: usable).process
        }
        for translation in stride(from: CGFloat(0), through: 130, by: 10) {   // down to exactly 70 pt
            sample(translation)
            XCTAssertTrue(navigation.showProcessArea, "\(translation) pt of travel leaves the area open")
        }
        sample(140)   // 60 pt proposed, the pointer still held
        XCTAssertFalse(navigation.showProcessArea, "closes the moment a sample proposes under 70 pt, before release")
        sample(100)   // the pointer comes back up before release: 100 pt proposed
        XCTAssertTrue(navigation.showProcessArea, "reversible until release")
        XCTAssertEqual(drawn(), 140, "reopened by the drag at the floor")
        sample(140)   // closes again, and the gesture ends here
        XCTAssertFalse(navigation.showProcessArea)
        navigation.showProcessArea = true   // the toggle's and ⌃⌘L's restore
        XCTAssertEqual(drawn(), 140, "reopens at the floor, the last open value the drag passed through — not at 200 pt")
    }

    // MARK: - New: the pane set and the sidebar (no mac4DSTEM/macTEM original; the old Bool pair and the Tools names)

    @MainActor func testTheDefaultsAreTheAppsDefaults() {
        let navigation = PanelNavigation()
        XCTAssertEqual(navigation.processFraction, 0)
        XCTAssertEqual(navigation.lastProcessFraction, LayoutPolicy.processAreaIdealFraction)
        XCTAssertFalse(navigation.showProcessArea)
        XCTAssertEqual(navigation.shownProcessPanes, [.output])
        XCTAssertTrue(navigation.showSidebarPane)
        XCTAssertFalse(navigation.showInspectorPane)
        XCTAssertFalse(navigation.sidebarCollapsedForWidth)
        XCTAssertTrue(navigation.sidebarIsVisible)
        XCTAssertFalse(navigation.inspectorIsVisible)
    }

    /// An open, empty area is not a valid state: opening with no pane shown shows Output.
    @MainActor func testOpeningWithNoPaneShownShowsOutput() {
        let navigation = PanelNavigation()
        navigation.shownProcessPanes = []
        navigation.showProcessArea = true
        XCTAssertEqual(navigation.shownProcessPanes, [.output])
        XCTAssertEqual(navigation.processFraction, LayoutPolicy.processAreaIdealFraction)
    }

    /// Hiding the last shown pane closes the area; showing a pane while the area is closed opens it; a second
    /// registered pane toggles independently.
    @MainActor func testTogglingPanesNeverLeavesTheAreaOpenAndEmpty() {
        let lineage = ProcessPaneID("lineage")
        let navigation = PanelNavigation()
        navigation.showProcessArea = true
        navigation.toggleProcessPane(lineage)
        XCTAssertEqual(navigation.shownProcessPanes, [.output, lineage])
        XCTAssertTrue(navigation.showProcessArea)

        navigation.toggleProcessPane(.output)
        XCTAssertEqual(navigation.shownProcessPanes, [lineage])
        XCTAssertTrue(navigation.showProcessArea, "a pane is still shown")

        navigation.toggleProcessPane(lineage)
        XCTAssertTrue(navigation.shownProcessPanes.isEmpty)
        XCTAssertFalse(navigation.showProcessArea, "hiding the last pane closes the area")

        navigation.toggleProcessPane(.output)
        XCTAssertEqual(navigation.shownProcessPanes, [.output])
        XCTAssertTrue(navigation.showProcessArea, "showing a pane while closed opens the area")
    }

    @MainActor func testProcessPaneIDIsReachableFromBothSpellings() {
        let nested: PanelNavigation.ProcessPaneID = .output
        XCTAssertEqual(nested, ProcessPaneID.output)
        XCTAssertEqual(ProcessPaneID("lineage").rawValue, "lineage")
    }

    /// The Show/Hide Sidebar action acts on what is on screen. Showing clears the width collapse; the collapse
    /// never clears itself, and does not touch the user's intent.
    @MainActor func testToggleSidebarActsOnWhatIsOnScreen() {
        let navigation = PanelNavigation()
        navigation.sidebarCollapsedForWidth = true
        XCTAssertFalse(navigation.sidebarIsVisible, "the window stepped it aside")
        XCTAssertTrue(navigation.showSidebarPane, "the intent survives the collapse")

        navigation.toggleSidebar()
        XCTAssertTrue(navigation.sidebarIsVisible, "showing clears the width collapse")
        XCTAssertFalse(navigation.sidebarCollapsedForWidth)

        navigation.toggleSidebar()
        XCTAssertFalse(navigation.sidebarIsVisible)
        XCTAssertFalse(navigation.showSidebarPane)
    }
}
