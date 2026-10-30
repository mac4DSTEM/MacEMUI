//
//  ZoomableImageTests.swift
//  The one zoomable container every room's picture sits in (`ZoomableImage`): it hands its content the pane's live zoom, so a
//  Metal view, an overlay of marks or a plain picture all draw with the same transform, and it carries every zoom route at once
//  (pinch and drag, the wheel and ⌥-scroll, the double click, VoiceOver's actions, the View menu). The routes' arithmetic is
//  `ZoomPan`'s and has its own tests; this file holds the container to it.
//

import SwiftUI
import XCTest
@testable import ShellControls

nonisolated final class ZoomableImageTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    @MainActor private final class Seen { var states: [ZoomPan] = [] }

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0)
    private static let blue = Color(.sRGB, red: 0, green: 0, blue: 1)

    /// The red share of a rendered pixel (sRGB bytes, whatever the byte order of the bitmap's alpha).
    @MainActor private func isRed(_ image: CGImage, x: Int, y: Int) throws -> Bool {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return px[0] > 200 && px[2] < 60
    }

    @MainActor private func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage, "the container renders")
    }

    /// The content is drawn with the pane's live zoom, a pinch in flight included, and laid out at the box. Red under: the content
    /// handed a fresh `ZoomPan` (or the committed zoom only) instead of the model's state.
    @MainActor func testTheContentIsHandedThePanesLiveZoom() throws {
        let model = PaneZoomModel()
        let box = CGSize(width: 200, height: 100)
        model.update { $0.step(by: 2, in: box, anchor: CGPoint(x: 40, y: 10)) }
        model.update { $0.pinch(magnification: 1.5, anchor: .zero, in: box) }
        let seen = Seen()
        let image = try render(ZoomableImage(model, box: box) { state in
            let _ = seen.states.append(state)
            Color.black
        })
        XCTAssertEqual(image.width, 200); XCTAssertEqual(image.height, 100)
        let handed = try XCTUnwrap(seen.states.last)
        XCTAssertEqual(handed, model.state)
        XCTAssertEqual(handed.effectiveZoom, 3, accuracy: 1e-12)
        XCTAssertNotEqual(handed.effectiveOffset, .zero)
    }

    /// A plain picture is placed by the shader's map: scaled about the box's centre by the drawn zoom, then moved by an unscaled offset.
    /// A 100 × 50 picture, red on its left half, at zoom 2 moved 20 points right: red runs from −30 to 70, so x 60 is red and x 80 is
    /// blue. Red under: the offset applied before the scale (it would be doubled to 40, and x 80 red too) or no zoom (x 60 blue).
    @MainActor func testAPlainPictureIsPlacedAsTheShaderPlacesIt() throws {
        let model = PaneZoomModel()
        let box = CGSize(width: 100, height: 50)
        model.update { $0.zoom = 2; $0.offset = CGSize(width: 20, height: 0) }
        let image = try render(ZoomableImage(model, box: box) { state in
            HStack(spacing: 0) { Self.red; Self.blue }.zoomPanPlacement(state)
        })
        XCTAssertTrue(try isRed(image, x: 60, y: 25))
        XCTAssertFalse(try isRed(image, x: 80, y: 25))
    }

    /// A letterboxed picture: with `pane`, the content is laid out and clipped at the pane, so a zoomed picture reaches into the
    /// letterbox, while the gestures stay a `box`-sized layer. Red under: the content clipped to the box (the corner stays empty).
    @MainActor func testALetterboxedPictureFillsThePane() throws {
        let model = PaneZoomModel()
        let image = try render(ZoomableImage(model, box: CGSize(width: 100, height: 50), pane: CGSize(width: 200, height: 100)) { _ in
            Self.red
        })
        XCTAssertEqual(image.width, 200); XCTAssertEqual(image.height, 100)
        XCTAssertTrue(try isRed(image, x: 5, y: 5), "the letterbox corner is the content's")
    }

    /// Every zoom route is on the container, measured against the same box: pinch, drag and the double click (`zoomPan`, with the
    /// pane's hover), the wheel and ⌥-scroll (`zoomPanWheel`), VoiceOver's zoom and pan actions, and View > Zoom (`zoomCommandTarget`).
    /// Red under: any route dropped.
    func testTheContainerCarriesEveryZoomRoute() throws {
        let file = squeezed(try source("Sources/ShellControls/ZoomableImage.swift"))
        XCTAssertTrue(file.contains("content.zoomPan(model, box: box, onHover: onHover).zoomPanWheel(model, box: box)"))
        XCTAssertTrue(file.contains("content.zoomPanAccessibilityActions(model, box: box).zoomCommandTarget(model, isTarget: isCommandTarget)"))
        XCTAssertTrue(file.contains(".contentShape(Rectangle()) .modifier(ZoomRoutes(model: model, box: box, wheel: wheel, onHover: onHover))"))
    }
}
