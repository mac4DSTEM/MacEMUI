// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEMTests/ZoomAnchorTests.swift (macTEM@51c944c macTEMTests/ZoomAnchorTests.swift folded in: its nonisolated class; macTEM cut the badge test, kept here because the badge moved too)
// Changes: `@testable import ShellControls`, app imports removed; class nonisolated, the three `PaneZoomModel` tests @MainActor; assertions identical.
// END MOVED FROM
//
//  ZoomAnchorTests.swift
//  Tier 2 (behaviour without a new number): zoom about the pointer, the zoom badge, and the model View > Zoom acts on.
//  UI audit 2026-10-14, "Zoom about the centre, no menu or wheel route". The invariant under test is the one the picture shows:
//  the image point under the anchor does not move when the zoom changes.
//

import XCTest
@testable import ShellControls

nonisolated final class ZoomAnchorTests: XCTestCase {
    private let box = CGSize(width: 400, height: 300)
    private var centre: CGPoint { CGPoint(x: box.width / 2, y: box.height / 2) }

    /// The views' own map: a box point `p` lands at `c + zoom * (p - c) + offset`.
    private func screen(_ p: CGPoint, _ z: ZoomPan) -> CGPoint {
        CGPoint(x: centre.x + z.effectiveZoom * (p.x - centre.x) + z.effectiveOffset.width,
                y: centre.y + z.effectiveZoom * (p.y - centre.y) + z.effectiveOffset.height)
    }

    /// The box point drawn at a screen point (the inverse).
    private func imagePoint(at s: CGPoint, _ z: ZoomPan) -> CGPoint {
        CGPoint(x: centre.x + (s.x - centre.x - z.effectiveOffset.width) / z.effectiveZoom,
                y: centre.y + (s.y - centre.y - z.effectiveOffset.height) / z.effectiveZoom)
    }

    private func assertSame(_ a: CGPoint, _ b: CGPoint, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-6, message, file: file, line: line)
    }

    // MARK: The invariant

    func testTheImagePointUnderThePointerStaysPutWhenZoomingIn() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            var z = ZoomPan()
            // A valid starting state: some zoom, an offset inside its clamp.
            z.zoom = CGFloat.random(in: 1...8, using: &rng)
            let limit = CGSize(width: box.width * (z.zoom - 1) / 2, height: box.height * (z.zoom - 1) / 2)
            z.offset = CGSize(width: CGFloat.random(in: -limit.width...limit.width, using: &rng),
                              height: CGFloat.random(in: -limit.height...limit.height, using: &rng))
            let pointer = CGPoint(x: CGFloat.random(in: 0...box.width, using: &rng),
                                  y: CGFloat.random(in: 0...box.height, using: &rng))
            let under = imagePoint(at: pointer, z)
            z.step(by: CGFloat.random(in: 1.05...2, using: &rng), in: box, anchor: ZoomPan.anchor(for: pointer, in: box))
            assertSame(screen(under, z), pointer, "zoom \(z.zoom) offset \(z.offset)")
        }
    }

    func testZoomingOutKeepsTheImageInsideThePaneAndTheAnchorWhereTheClampAllows() {
        var z = ZoomPan()
        let pointer = CGPoint(x: 380, y: 20)
        z.step(by: 4, in: box, anchor: ZoomPan.anchor(for: pointer, in: box))
        // Out by 2 about the same point: the clamp may bind near an edge, but never lets the image leave the pane.
        z.step(by: 0.5, in: box, anchor: ZoomPan.anchor(for: pointer, in: box))
        let limit = CGSize(width: box.width * (z.zoom - 1) / 2, height: box.height * (z.zoom - 1) / 2)
        XCTAssertLessThanOrEqual(abs(z.offset.width), limit.width + 1e-9)
        XCTAssertLessThanOrEqual(abs(z.offset.height), limit.height + 1e-9)
        z.step(by: 0.25, in: box, anchor: ZoomPan.anchor(for: pointer, in: box))
        XCTAssertEqual(z.zoom, 0.5)
        XCTAssertEqual(z.offset, .zero, "below 1x the image is centred")
    }

    func testTheCentreAnchorScalesTheOffsetAndKeepsTheViewCentreOnTheSamePoint() {
        var z = ZoomPan()
        z.zoom = 2
        z.offset = CGSize(width: 100, height: -60)
        let under = imagePoint(at: centre, z)
        z.step(by: 2, in: box)                                      // the default anchor: the pane's centre
        assertSame(screen(under, z), centre)
        XCTAssertEqual(z.offset, CGSize(width: 200, height: -120))
    }

    func testAnchoredOffsetIsTheIdentityWhenTheZoomDoesNotChange() {
        let o = CGSize(width: 12, height: -7)
        XCTAssertEqual(ZoomPan.anchoredOffset(o, from: 3, to: 3, anchor: CGPoint(x: 50, y: 40)), o)
    }

    // MARK: A pinch in flight and at its end

    func testAPinchInFlightShowsWhatItWillCommit() {
        let pointer = CGPoint(x: 120, y: 210)
        let anchor = ZoomPan.anchor(for: pointer, in: box)
        var live = ZoomPan()
        live.step(by: 2, in: box)
        let under = imagePoint(at: pointer, live)
        live.pinch(magnification: 1.5, anchor: anchor, in: box)
        XCTAssertEqual(live.effectiveZoom, 3, accuracy: 1e-9)
        assertSame(screen(under, live), pointer, "the pixel under the pointer is still under it mid-pinch")
        var committed = ZoomPan()
        committed.step(by: 2, in: box)
        committed.endPinch(magnification: 1.5, anchor: anchor, in: box)
        XCTAssertEqual(committed.liveZoom, 1)
        XCTAssertEqual(committed.liveOffset, .zero)
        XCTAssertEqual(committed.zoom, live.effectiveZoom, accuracy: 1e-9)
        assertSame(CGPoint(x: committed.offset.width, y: committed.offset.height),
                   CGPoint(x: live.effectiveOffset.width, y: live.effectiveOffset.height))
    }

    func testAPinchPastTheLimitsShowsTheLimitNotMore() {
        var z = ZoomPan()
        z.pinch(magnification: 1000, anchor: .zero, in: box)
        XCTAssertEqual(z.effectiveZoom, ZoomPan.maximumZoom, "live display stops where the commit will")
        z.pinch(magnification: 0.0001, anchor: .zero, in: box)
        XCTAssertEqual(z.effectiveZoom, ZoomPan.minimumZoom)
        z.endPinch(magnification: 0.0001, anchor: .zero, in: box)
        XCTAssertEqual(z.zoom, ZoomPan.minimumZoom)
        XCTAssertEqual(z.liveZoom, 1)
    }

    // MARK: Badge

    func testTheBadgeNamesTheZoomAndIsQuietAtOneX() {
        let us = Locale(identifier: "en_US_POSIX"), de = Locale(identifier: "de_DE")
        XCTAssertNil(ZoomPan.badgeText(zoom: 1, locale: us))
        XCTAssertNil(ZoomPan.badgeText(zoom: 1.002, locale: us), "float dust around 1x says nothing")
        XCTAssertEqual(ZoomPan.badgeText(zoom: 2, locale: us), "\u{00D7}2")
        XCTAssertEqual(ZoomPan.badgeText(zoom: 2.5, locale: us), "\u{00D7}2.5")
        XCTAssertEqual(ZoomPan.badgeText(zoom: 0.5, locale: us), "\u{00D7}0.5")
        XCTAssertEqual(ZoomPan.badgeText(zoom: 12.34, locale: us), "\u{00D7}12.3")
        XCTAssertEqual(ZoomPan.badgeText(zoom: 64, locale: us), "\u{00D7}64")
        XCTAssertEqual(ZoomPan.badgeText(zoom: 2.5, locale: de), "\u{00D7}2,5", "the reader's decimal separator")
        XCTAssertEqual(ZoomPan.badgeSpoken(zoom: 2.5, locale: us), "Zoomed to 2.5 times")
        XCTAssertNil(ZoomPan.badgeSpoken(zoom: 1, locale: us))
    }

    // MARK: The model View > Zoom acts on

    @MainActor func testTheCommandsZoomAboutThePointerWhenItIsOverThePaneAndTheCentreWhenNot() {
        let model = PaneZoomModel()
        model.box = box
        model.zoomIn()
        XCTAssertEqual(model.state.zoom, 2)
        XCTAssertEqual(model.state.offset, .zero, "no pointer: about the centre")

        model.fit()
        model.pointer = CGPoint(x: 300, y: 150)                      // 100 points right of the centre, on its row
        let under = imagePoint(at: model.pointer!, model.state)
        model.zoomIn()
        assertSame(screen(under, model.state), model.pointer!)
        XCTAssertEqual(model.state.offset, CGSize(width: -100, height: 0))

        model.zoomOut()
        XCTAssertEqual(model.state.zoom, 1)
        XCTAssertEqual(model.state.offset, .zero)
    }

    @MainActor func testFitIsWhatADoubleClickDoes() {
        let model = PaneZoomModel()
        model.box = box
        model.pointer = CGPoint(x: 10, y: 10)
        model.zoomIn(); model.zoomIn()
        model.update { $0.liveOffset = CGSize(width: 3, height: 3) }
        model.fit()
        XCTAssertEqual(model.state, ZoomPan())
    }

    @MainActor func testTheLimitsAreThePinchsLimits() {
        let model = PaneZoomModel()
        model.box = box
        for _ in 0..<20 { model.zoomIn() }
        XCTAssertEqual(model.state.zoom, ZoomPan.maximumZoom)
        for _ in 0..<20 { model.zoomOut() }
        XCTAssertEqual(model.state.zoom, ZoomPan.minimumZoom)
    }
}
