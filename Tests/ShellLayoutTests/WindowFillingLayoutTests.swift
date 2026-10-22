// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEMTests/NavigationSeamTests.swift (the two S6 Frozen Shell tests of `WindowFillingLayout`; the rest of that file tests AppState and stays) (macTEM@51c944c: no differences folded in)
// Changes: `@testable import ShellLayout`; assertions unchanged
// END MOVED FROM

import SwiftUI
import XCTest
@testable import ShellLayout

nonisolated final class WindowFillingLayoutTests: XCTestCase {
    // MARK: S6 Frozen Shell (2026-09-30)

    /// The window-width probe answers a finite proposal with itself, whatever
    /// the child needs. Red under the old shape (the split measured directly:
    /// 1190 in a 915-pt window) and under `max(proposal, child)`.
    @MainActor
    func testWindowFillingLayoutReportsTheOfferedSizeNotTheRigidChild() {
        let rigid = CGSize(width: 1190, height: 700)
        let reported = WindowFillingLayout.reportedSize(
            proposal: ProposedViewSize(width: 915, height: 600), child: rigid)
        XCTAssertEqual(reported.width, 915)
        XCTAssertEqual(reported.height, 600)
        // The sidebar's step-aside line reads that width: 915 < 1095.
        XCTAssertFalse(LayoutPolicy.navigatorFits(windowWidth: reported.width, inspectorVisible: true))
    }

    /// An ideal or unbounded query still goes to the child, so the window's
    /// ideal and maximum sizes are unchanged. Red if the layout answered 0 or
    /// infinity for those.
    @MainActor
    func testWindowFillingLayoutDefersIdealAndUnboundedQueriesToTheChild() {
        let child = CGSize(width: 1280, height: 800)
        let ideal = WindowFillingLayout.reportedSize(proposal: .unspecified, child: child)
        XCTAssertEqual(ideal, child)
        let unbounded = WindowFillingLayout.reportedSize(
            proposal: ProposedViewSize(width: .infinity, height: 500), child: child)
        XCTAssertEqual(unbounded.width, 1280)
        XCTAssertEqual(unbounded.height, 500)
    }
}
