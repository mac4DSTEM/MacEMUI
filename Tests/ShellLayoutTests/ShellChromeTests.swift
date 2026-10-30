// Written new for MacEMShell (suite task 8): the pure decisions of the window chrome, ShellLayout/Chrome. Sources noted per test.

import SwiftUI
import XCTest
@testable import ShellLayout

/// A stand-in for an app's room enum: three rooms, the last not built.
private nonisolated enum TestRoom: String, CaseIterable, WorkspaceRoom {
    case prepare, image, edx

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbolName: String { "circle" }
    var subtitle: String { "The \(rawValue) room" }
    var isAvailable: Bool { self != .edx }
}

/// Twelve rooms, to meet the ⌘9 limit.
private nonisolated struct NumberedRoom: WorkspaceRoom, CaseIterable {
    let number: Int
    var id: String { "room\(number)" }
    var title: String { id }
    var symbolName: String { "circle" }
    var subtitle: String { "" }
    var shortcutNumber: Int? { number <= 9 ? number : nil }
    static let allCases = (1...12).map(NumberedRoom.init(number:))
}

nonisolated final class ShellChromeTests: XCTestCase {

    // MARK: - Rooms (macTEM `WorkspaceArea.shortcutDigit`, mac4DSTEM Workspace menu)

    func testAShortcutIsTheRoomsPlaceInTheList() {
        XCTAssertEqual(TestRoom.prepare.shortcutNumber, 1)
        XCTAssertEqual(TestRoom.image.shortcutNumber, 2)
        XCTAssertEqual(TestRoom.edx.shortcutNumber, 3)
        XCTAssertEqual(TestRoom.image.shortcutKey, KeyEquivalent("2"))
    }

    func testNoRoomPastTheNinthGetsAShortcut() {
        XCTAssertEqual(NumberedRoom(number: 9).shortcutNumber, 9)
        XCTAssertNil(NumberedRoom(number: 10).shortcutNumber)
        XCTAssertNil(NumberedRoom(number: 10).shortcutKey)
    }

    func testTheMenuMapsANumberToItsRoomAndSkipsAnUnavailableOne() {
        XCTAssertEqual(WorkspaceRoomShortcuts.room(forShortcut: 2, in: TestRoom.allCases), .image)
        XCTAssertNil(WorkspaceRoomShortcuts.room(forShortcut: 3, in: TestRoom.allCases),
                     "a room not built is listed and cannot be entered")
        XCTAssertNil(WorkspaceRoomShortcuts.room(forShortcut: 7, in: TestRoom.allCases))
    }

    // MARK: - The room's verb (mac4DSTEM `PrimaryActionButton`)

    func testTheVerbIsProminentOnlyWhenItCanRun() {
        XCTAssertEqual(PrimaryActionPresentation.of(title: "Compute Image", isEnabled: true, isRunning: false, canStop: false),
                       .verb(prominent: true))
        XCTAssertEqual(PrimaryActionPresentation.of(title: "Compute Image", isEnabled: false, isRunning: false, canStop: false),
                       .verb(prominent: false), "a blocked verb never draws the accent fill (drive 2026-09-30)")
    }

    func testARunReplacesTheVerbWithCancelOrASpinner() {
        XCTAssertEqual(PrimaryActionPresentation.of(title: "Compute Image", isEnabled: true, isRunning: true, canStop: true), .cancel)
        XCTAssertEqual(PrimaryActionPresentation.of(title: "Compute Image", isEnabled: true, isRunning: true, canStop: false), .spinner)
        XCTAssertEqual(PrimaryActionPresentation.of(title: nil, isEnabled: false, isRunning: true, canStop: true), .cancel,
                       "a room with no verb still offers Cancel for a run in flight")
    }

    func testNoVerbAndNothingRunningShowsNothing() {
        XCTAssertEqual(PrimaryActionPresentation.of(title: nil, isEnabled: false, isRunning: false, canStop: false), .hidden)
    }

    @MainActor
    func testAPrimaryActionDefaultsToCommandReturnAndNilMeansHidden() {
        let action = PrimaryAction(title: "Quantify", run: {})
        XCTAssertEqual(action.keyEquivalent, .return)
        XCTAssertEqual(action.modifiers, .command)
        XCTAssertTrue(action.isEnabled)
        XCTAssertFalse(action.isRunning)
        XCTAssertEqual(PrimaryActionPresentation.of(action), .verb(prominent: true))
        XCTAssertEqual(PrimaryActionPresentation.of(nil), .hidden)
        let running = PrimaryAction(title: "Quantify", isRunning: true, stop: {}, run: {})
        XCTAssertEqual(PrimaryActionPresentation.of(running), .cancel)
    }

    // MARK: - The toolbar's display (mac4DSTEM StatusBarMetricsTests)

    /// The toolbar's idle display (owner, 2026-09-22 evening): the file
    /// first — it is the window's subject — then the room, then the scan
    /// size, so "Demo.h5 · Prepare · 4,050 positions" reads the same as the
    /// Run tab's counts. (mac4DSTEM's test built the size from `SystemMonitor.count`; the size is the app's ready text now.)
    func testTheToolbarIdleDisplayNamesFileRoomAndDetailInThatOrder() {
        let line = ToolbarDisplayFormat.idle(file: "Demo.h5", room: "Prepare", detail: "\(SystemMonitor.count(4050)) positions")
        XCTAssertEqual(line, "Demo.h5 · Prepare · \(SystemMonitor.count(4050)) positions")
        XCTAssertTrue(line.hasPrefix("Demo.h5"), "the file leads")
        XCTAssertTrue(line.hasSuffix("positions"))
    }

    func testTheBusyDisplayIsTheOperationThenElapsedThenAnEtaOnlyOnceKnown() {
        XCTAssertEqual(ToolbarDisplayFormat.busy(operation: "Detect Disks", elapsed: nil, eta: nil), "Detect Disks")
        XCTAssertEqual(ToolbarDisplayFormat.busy(operation: "Detect Disks", elapsed: 53, eta: nil), "Detect Disks · 53 s")
        XCTAssertEqual(ToolbarDisplayFormat.busy(operation: "Detect Disks", elapsed: 155, eta: 42),
                       "Detect Disks · 2:35 · ETA 42 s")
    }

    /// The spoken clock is the drawn clock: both come from one reading at one tick, so 4 s on screen is 4 s for
    /// VoiceOver and UI tests, never the first tick 0 s (MacEMUI#39).
    func testTheBusyLineLabelReadsTheSameTickAsTheDrawnClock() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let metrics: (Date) -> (elapsed: TimeInterval, eta: TimeInterval?)? = { date in
            (elapsed: date.timeIntervalSince(start), eta: nil)
        }
        let tick = ToolbarDisplayFormat.busyTick(operation: "Detect Disks", progress: 0.4, metrics: metrics,
                                                 at: start.addingTimeInterval(4))
        XCTAssertEqual(tick.text, "Detect Disks · 4 s")
        XCTAssertEqual(tick.accessibilityLabel, tick.text)
        XCTAssertEqual(tick.accessibilityValue, "40 percent")
        let first = ToolbarDisplayFormat.busyTick(operation: "Detect Disks", progress: nil, metrics: metrics,
                                                  at: start)
        XCTAssertEqual(first.accessibilityLabel, "Detect Disks · 0 s")
        XCTAssertEqual(first.accessibilityValue, "")
    }

    // MARK: - Panel intent (mac4DSTEM ContentView)

    /// The keys are what saved windows already hold: moving to the package must not reset anyone's panels.
    func testTheSceneStorageKeysAreTheOnesTheAppsWriteToday() {
        XCTAssertEqual(ShellStorageKeys.sidebarVisible, "workspace.navigatorVisible")
        XCTAssertEqual(ShellStorageKeys.inspectorVisible, "workspace.inspectorVisible")
        XCTAssertEqual(ShellStorageKeys.processFraction, "workspace.processFraction")
        XCTAssertEqual(ShellStorageKeys.lastProcessFraction, "workspace.lastProcessFraction")
        XCTAssertEqual(ShellStorageKeys.paneSplitFraction, "workspace.paneSplit.fraction")
        XCTAssertEqual(ShellStorageKeys.processSplitFraction, "workspace.processSplit.fraction")
        XCTAssertEqual(ShellStorageKeys.inspectorTab, "inspector.tab")
    }

    func testTheLaunchFlagsForcePanelsAndAnAbsentFlagSaysNothing() {
        XCTAssertEqual(ShellLaunchFlags.panels(arguments: ["app"]), .init())
        XCTAssertEqual(ShellLaunchFlags.panels(arguments: ["--inspector-hidden", "--navigator-shown", "--process-area-open"]),
                       .init(inspector: false, sidebar: true, processArea: true))
        // Shown wins over hidden when both are passed, as the later `if` did in ContentView.
        XCTAssertEqual(ShellLaunchFlags.panels(arguments: ["--inspector-hidden", "--inspector-shown"]).inspector, true)
    }

    // MARK: - The step-aside line (LayoutPolicy.navigatorFits, as ContentView asks it)

    func testTheSidebarStepsAsideBelowTheLineAndNotAboveIt() {
        let line = LayoutPolicy.navigatorLine(inspectorVisible: true)
        XCTAssertFalse(LayoutPolicy.navigatorFits(windowWidth: line - 1, inspectorVisible: true))
        XCTAssertTrue(LayoutPolicy.navigatorFits(windowWidth: line, inspectorVisible: true))
        // The inspector hidden moves the line left; the window's ideal width is always above it.
        XCTAssertLessThan(LayoutPolicy.navigatorLine(inspectorVisible: false), line)
        XCTAssertTrue(LayoutPolicy.navigatorFits(windowWidth: LayoutPolicy.datasetWindowIdealSize.width, inspectorVisible: true))
    }

    // MARK: - PaneSplit

    /// Below two floors the fraction saturates at one half: the split divides what it has evenly.
    func testThePaneSplitFloorSaturatesAtOneHalf() {
        XCTAssertEqual(PaneSplit<EmptyView, EmptyView>.smallestFraction(minimumPane: 180, usable: 900), 0.2, accuracy: 1e-12)
        XCTAssertEqual(PaneSplit<EmptyView, EmptyView>.smallestFraction(minimumPane: 180, usable: 300), 0.5)
        XCTAssertEqual(PaneSplit<EmptyView, EmptyView>.smallestFraction(minimumPane: 180, usable: 100), 0.5)
    }

    // MARK: - Process tabs

    @MainActor
    func testTheOutputTabIsRegisteredUnderTheOutputPaneID() {
        let tab = ProcessTab.output { EmptyView() }
        XCTAssertEqual(tab.id, .output)
        XCTAssertEqual(tab.title, "Output")
    }
}
