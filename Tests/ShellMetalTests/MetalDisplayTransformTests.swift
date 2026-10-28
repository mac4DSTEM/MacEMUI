import XCTest
@testable import ShellMetal

/// The shader zoom (2026-10-12) draws the image through one affine map that
/// inverts the SwiftUI chain applied to the overlays. These pin the pure map;
/// a wrong sign, a missing letterbox term or an identity-only body each fails
/// at least one test below.
nonisolated final class MetalDisplayTransformTests: XCTestCase {

    private let pane = CGSize(width: 400, height: 400)

    private func assertPoint(
        _ p: CGPoint, _ x: Double, _ y: Double, accuracy: Double = 1e-9,
        _ message: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(Double(p.x), x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(Double(p.y), y, accuracy: accuracy, message, file: file, line: line)
    }

    /// Identity-only passes this; any implementation that ignores paneSize fails.
    func testIdentityMapsCornersAndCentre() {
        let t = MetalDisplayTransform.identity(pane)
        assertPoint(t.uv(atPanePoint: CGPoint(x: 0, y: 0)), 0, 0)
        assertPoint(t.uv(atPanePoint: CGPoint(x: 400, y: 400)), 1, 1)
        assertPoint(t.uv(atPanePoint: CGPoint(x: 200, y: 200)), 0.5, 0.5)
        let rows = t.shaderRows()
        XCTAssertEqual(rows.0, SIMD4<Float>(1, 0, 0, 0))
        XCTAssertEqual(rows.1, SIMD4<Float>(0, 1, 0, 0))
    }

    /// Zoom 2 about the pane centre: (100,100) -> 0.375 (image point 150 of 400). A multiply instead of divide gives
    /// 0.0 style values; a zoom that ignores the pane centre gives 0.5 at (200,200)
    /// only by accident but fails (100,100).
    func testZoomIsAboutThePaneCentre() {
        let t = MetalDisplayTransform(paneSize: pane, imageBox: pane, zoom: 2)
        assertPoint(t.uv(atPanePoint: CGPoint(x: 100, y: 100)), 0.375, 0.375)   // (100 - 200) / 2 + 200 = 150 of 400
        assertPoint(t.uv(atPanePoint: CGPoint(x: 200, y: 200)), 0.5, 0.5)
    }

    /// Offset (200,0) pushes the zoom-2 image right to its left edge, so pane
    /// (0,200) shows uv (0, 0.5). A flipped offset sign gives uv.x = 0.5.
    func testOffsetMovesTheImageWithTheFingerNotAgainstIt() {
        let t = MetalDisplayTransform(
            paneSize: pane, imageBox: pane, zoom: 2, offset: CGSize(width: 200, height: 0))
        assertPoint(t.uv(atPanePoint: CGPoint(x: 0, y: 200)), 0, 0.5)
    }

    /// Letterbox: a 400x200 box in a 400 pane. Without the imageBox term (uv =
    /// pane/paneSize) the pane centre-top (200,100) would be (0.5, 0.25).
    func testLetterboxedImageBoxIsCentredInThePane() {
        let t = MetalDisplayTransform(
            paneSize: pane, imageBox: CGSize(width: 400, height: 200), zoom: 1)
        assertPoint(t.uv(atPanePoint: CGPoint(x: 200, y: 100)), 0.5, 0)
        XCTAssertLessThan(t.uv(atPanePoint: CGPoint(x: 200, y: 50)).y, 0, "above the image is outside")
        XCTAssertGreaterThan(t.uv(atPanePoint: CGPoint(x: 200, y: 350)).y, 1, "below the image is outside")
    }

    /// Rotation 90 clockwise: image top-left shows at the pane's top-RIGHT. The
    /// counter-clockwise sign puts uv(399,1) near (1,1) instead of (0,0).
    /// Mirrored at 0: pane (1,1) -> uv (1,0); no mirror gives (0,0).
    func testRotationIsClockwiseAndMirrorFlipsX() {
        let rot = MetalDisplayTransform(paneSize: pane, imageBox: pane, rotationDegrees: 90)
        assertPoint(rot.uv(atPanePoint: CGPoint(x: 399, y: 1)), 0.0025, 0.0025)
        let mir = MetalDisplayTransform(paneSize: pane, imageBox: pane, mirrored: true)
        assertPoint(mir.uv(atPanePoint: CGPoint(x: 1, y: 1)), 0.9975, 0.0025)
    }

    /// The forward SwiftUI chain round-trips through uv(atPanePoint:), and the
    /// shader rows are the same map on q = p / paneSize. Order errors (mirror
    /// before rotation, offset before zoom) fail the round-trip for random draws.
    func testForwardChainRoundTripsAndRowsAgree() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let paneSize = CGSize(width: Double.random(in: 200...600, using: &rng),
                                  height: Double.random(in: 200...600, using: &rng))
            let box = CGSize(width: Double.random(in: 100...400, using: &rng),
                             height: Double.random(in: 100...400, using: &rng))
            let t = MetalDisplayTransform(
                paneSize: paneSize, imageBox: box,
                zoom: CGFloat(Double.random(in: 0.25...16, using: &rng)),
                offset: CGSize(width: Double.random(in: -300...300, using: &rng),
                               height: Double.random(in: -300...300, using: &rng)),
                rotationDegrees: [0, 90, 180, 270].randomElement(using: &rng)!,
                mirrored: Bool.random(using: &rng))

            // Forward chain on an image-local point.
            let p = CGPoint(x: Double.random(in: 0...Double(box.width), using: &rng),
                            y: Double.random(in: 0...Double(box.height), using: &rng))
            let pcx = Double(p.x - box.width / 2), pcy = Double(p.y - box.height / 2)
            let th = t.rotationDegrees * Double.pi / 180
            let rx = cos(th) * pcx - sin(th) * pcy
            let ry = sin(th) * pcx + cos(th) * pcy
            let mx = t.mirrored ? -rx : rx
            let z = Double(t.zoom)
            let screen = CGPoint(x: z * mx + Double(t.offset.width) + Double(paneSize.width) / 2,
                                 y: z * ry + Double(t.offset.height) + Double(paneSize.height) / 2)
            let back = t.uv(atPanePoint: screen)
            assertPoint(back, Double(p.x / box.width), Double(p.y / box.height),
                        accuracy: 1e-9, "\(t)")

            // Shader rows on q = screen / paneSize.
            let rows = t.shaderRows()
            let qx = Double(screen.x / paneSize.width), qy = Double(screen.y / paneSize.height)
            let u = Double(rows.0.x) * qx + Double(rows.0.y) * qy + Double(rows.0.z)
            let v = Double(rows.1.x) * qx + Double(rows.1.y) * qy + Double(rows.1.z)
            let expect = t.uv(atPanePoint: screen)
            assertPoint(CGPoint(x: u, y: v), Double(expect.x), Double(expect.y),
                        accuracy: 1e-3 * max(1, z), "rows \(t)")
        }
    }
}
