//
//  Pins `MenuActionRelay`, the hand-off of a File-menu command (Open…, ⌘O) to a window that does not exist yet:
//  a request is taken exactly once (a second window appearing later does not repeat it), a second request before
//  the take replaces the first, the count the window watches rises with every request, and `isEnabled` is enabled
//  with no focused window and with one unless that window is blocked (an open in flight).
//

import XCTest
@testable import ShellLayout

nonisolated final class MenuActionRelayTests: XCTestCase {
    private nonisolated enum TestAction: Equatable {
        case open
        case preprocess
    }

    @MainActor func testARequestIsTakenExactlyOnce() {
        let relay = MenuActionRelay<TestAction>()
        XCTAssertNil(relay.take(), "nothing asked for, nothing to take")
        relay.request(.open)
        XCTAssertEqual(relay.pendingAction, .open)
        XCTAssertEqual(relay.take(), .open)
        XCTAssertNil(relay.pendingAction)
        XCTAssertNil(relay.take(), "the next window to appear does not repeat the action")
    }

    /// The count the window watches rises with every request, so a minimised window (whose `.task` does not run
    /// again) is told; taking does not lower it. Red under: `request` not raising `requestCount`.
    @MainActor func testEveryRequestRaisesTheCountTheWindowWatches() {
        let relay = MenuActionRelay<TestAction>()
        let before = relay.requestCount
        relay.request(.open)
        XCTAssertEqual(relay.requestCount, before &+ 1)
        _ = relay.take()
        relay.request(.open)
        XCTAssertEqual(relay.requestCount, before &+ 2)
    }

    @MainActor func testASecondRequestBeforeTheTakeIsStillOneAction() {
        let relay = MenuActionRelay<TestAction>()
        relay.request(.open)
        relay.request(.open)
        XCTAssertEqual(relay.take(), .open)
        XCTAssertNil(relay.take())
    }

    /// Mutation it catches: a request that only sets when nothing is pending (the FIRST gesture wins).
    @MainActor func testTheLatestRequestWins() {
        let relay = MenuActionRelay<TestAction>()
        relay.request(.open)
        relay.request(.preprocess)
        XCTAssertEqual(relay.take(), .preprocess)
        XCTAssertNil(relay.take())
    }

    func testIsEnabledTruthTable() {
        // (hasFocusedWindow, blocked) → enabled.
        let table: [(Bool, Bool, Bool)] = [
            (false, false, true),   // no window: the item opens one
            (false, true, true),    // no window: nothing can block it
            (true, false, true),
            (true, true, false),    // the focused window is mid-open
        ]
        for (focused, blocked, enabled) in table {
            XCTAssertEqual(MenuActionRelay<TestAction>.isEnabled(hasFocusedWindow: focused, blocked: blocked), enabled,
                           "focused \(focused), blocked \(blocked)")
        }
    }
}
