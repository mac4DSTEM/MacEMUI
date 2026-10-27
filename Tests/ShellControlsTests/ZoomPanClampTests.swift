import XCTest
@testable import ShellControls
/// Panning may reveal the image's edge but
/// must never push the image out of the pane. Pins the pure rule the
/// gesture/scroll handlers all route through — |offset| ≤ size·(zoom − 1)/2,
/// the scaled image's overhang per side (the views offset in screen points
/// after `scaleEffect`).
nonisolated final class ZoomPanClampTests: XCTestCase {

    func testPanIsBlockedAtOneXAndBelow() {
        let size = CGSize(width: 400, height: 300)
        XCTAssertEqual(
            ZoomPan.clampedOffset(CGSize(width: 50, height: -80), zoom: 1, in: size),
            .zero, "at 1× the image fills the pane — a plain click scrubs, panning is meaningless"
        )
        XCTAssertEqual(
            ZoomPan.clampedOffset(CGSize(width: 50, height: -80), zoom: 0.5, in: size),
            .zero, "zoomed out, the image fits entirely — it stays centred"
        )
    }

    func testZoomedPanStopsExactlyAtTheEdge() {
        let size = CGSize(width: 400, height: 300)
        // zoom 2 → limit size·(2 − 1)/2 = size/2 = (200, 150).
        let clamped = ZoomPan.clampedOffset(
            CGSize(width: 500, height: -500), zoom: 2, in: size
        )
        XCTAssertEqual(clamped.width, 200)
        XCTAssertEqual(clamped.height, -150)
        // Inside the band, the pan passes through untouched.
        XCTAssertEqual(
            ZoomPan.clampedOffset(CGSize(width: 40, height: -60), zoom: 2, in: size),
            CGSize(width: 40, height: -60)
        )
    }

    func testZoomFourReachesItsOwnEdge() {
        let size = CGSize(width: 400, height: 300)
        // zoom 4 → limit size·3/2 = (600, 450): the scaled image's far edge meets the pane edge.
        XCTAssertEqual(
            ZoomPan.clampedOffset(CGSize(width: 5000, height: -5000), zoom: 4, in: size),
            CGSize(width: 600, height: -450)
        )
    }

    func testMidRangePanPassesThroughUnclamped() {
        let size = CGSize(width: 400, height: 300)
        // zoom 1.5 → limit (100, 75): (60, −70) is inside it and must not be pulled back.
        XCTAssertEqual(
            ZoomPan.clampedOffset(CGSize(width: 60, height: -70), zoom: 1.5, in: size),
            CGSize(width: 60, height: -70)
        )
    }

    func testZoomingOutPullsAPannedImageBackInside() {
        let size = CGSize(width: 400, height: 400)
        // Panned to the zoom-4 limit (600pt), then the zoom drops to 2:
        // the limit is now 200pt and the offset must come back with it.
        XCTAssertEqual(
            ZoomPan.clampedOffset(CGSize(width: 600, height: 600), zoom: 2, in: size),
            CGSize(width: 200, height: 200)
        )
    }
}
