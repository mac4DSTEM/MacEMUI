//
//  MapTileViewportTests.swift
//  A map tile sits in the shared `ImageViewport` (one container for zoom and pan) and keeps the room's one `MapViewTransform`:
//  each tile's pane zoom is that transform in the tile's own points, a gesture in flight on one tile is shared live and never
//  echoed back onto it, and nothing goes below the fit. The app's overlay is drawn over the picture and zooms with it.
//

import SwiftUI
import XCTest
@testable import ShellSpectroscopy
import ShellControls

nonisolated final class MapTileViewportTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// The pane state of a tile is the shared transform with its offset in the tile's points, and reads back to the same transform.
    /// Red under: the offset left in tile fractions (a 200-point tile would pan by a fraction of a point).
    func testATilesPaneStateIsTheSharedTransformInItsPoints() {
        var t = MapViewTransform()
        t.zoom(by: 2, about: CGPoint(x: 0.25, y: 0.25))
        let size = CGSize(width: 200, height: 100)
        let pane = t.paneState(in: size)
        XCTAssertEqual(pane.zoom, 2)
        XCTAssertEqual(pane.offset.width, t.zoomPan.offset.width * 200, accuracy: 1e-12)
        XCTAssertEqual(pane.offset.height, t.zoomPan.offset.height * 100, accuracy: 1e-12)
        XCTAssertNotEqual(pane.offset, .zero)
        let back = MapViewTransform(pane: pane, in: size)
        XCTAssertEqual(back.zoom, t.zoom)
        XCTAssertEqual(back.center.x, t.center.x, accuracy: 1e-12); XCTAssertEqual(back.center.y, t.center.y, accuracy: 1e-12)
    }

    /// The panes zoom out to a quarter; the maps never below the fit. A tile that committed a zoom below the fit (the wheel, a pinch,
    /// VoiceOver) is put back on the fit and shares the fit. Red under: a tile left smaller than its frame.
    func testATileBelowTheFitReturnsToTheFit() {
        let size = CGSize(width: 120, height: 80)
        var below = ZoomPan()
        below.step(by: 0.5, in: size)
        XCTAssertEqual(below.zoom, 0.5)
        XCTAssertEqual(MapViewTransform(pane: below, in: size), MapViewTransform())
        var zoomed = MapViewTransform(); zoomed.zoom(by: 3, about: CGPoint(x: 0.5, y: 0.5))
        let sync = MapTileZoomSync.fromPane(below, shared: zoomed, size: size)
        XCTAssertEqual(sync.shared, MapViewTransform(), "the room shares the fit")
        XCTAssertEqual(sync.pane, ZoomPan(), "the tile is put back on the fit")
        XCTAssertNil(MapTileZoomSync.fromPane(ZoomPan(), shared: MapViewTransform(), size: size).shared, "nothing changed, nothing written")
    }

    /// A pinch in flight on one tile: the other tiles follow it live (the shared transform is its effective zoom), and the shared
    /// transform coming back is not put onto the pinching tile (that would commit its live zoom and double the pinch). Once the
    /// gesture ends, the shared transform reaches every tile. Red under: the echo written back mid-gesture, or the live zoom not shared.
    @MainActor func testAGestureInFlightIsSharedLiveAndNotEchoed() {
        let size = CGSize(width: 200, height: 200)
        var pinching = ZoomPan()
        pinching.pinch(magnification: 2, anchor: .zero, in: size)
        let sync = MapTileZoomSync.fromPane(pinching, shared: MapViewTransform(), size: size)
        XCTAssertEqual(sync.shared?.zoom, 2, "the other tiles follow the pinch live")
        XCTAssertNil(sync.pane, "the pinching tile keeps its gesture")
        XCTAssertNil(MapTileZoomSync.fromShared(sync.shared!, pane: pinching, size: size), "no echo onto the tile in a gesture")
        let idle = MapTileZoomSync.fromShared(sync.shared!, pane: ZoomPan(), size: CGSize(width: 100, height: 50))
        XCTAssertEqual(idle?.zoom, 2, "a tile at rest takes the shared zoom")
        XCTAssertNil(MapTileZoomSync.fromShared(sync.shared!, pane: idle!, size: CGSize(width: 100, height: 50)), "and is then left alone")
    }

    /// The overlay slot: the app's drawing sits over the picture, laid out at the tile in the picture's own points, and zooms and pans
    /// with it; it is handed the live zoom (for strokes of a constant width) and the scan's grid. A red bar over the left eighth of the
    /// picture is at x 12 at the fit; zoomed 2× about the centre that eighth is out of view. Red under: no slot, the overlay drawn
    /// outside the zooming content (red at x 12 when zoomed), or the zoom not handed over.
    @MainActor func testTheOverlayIsDrawnOverThePictureAndZoomsWithIt() throws {
        final class Seen { var contexts: [MapTileOverlayContext] = [] }
        let size = CGSize(width: 200, height: 100)
        func render(_ transform: MapViewTransform, seen: Seen) throws -> CGImage {
            let tile = MapTileView(title: "Fe", image: nil, size: size, scanWidth: 40, scanHeight: 20, transform: .constant(transform),
                                   onHover: { _ in }, controls: { EmptyView() },
                                   overlay: { context in
                                       let _ = seen.contexts.append(context)
                                       HStack(spacing: 0) {
                                           Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: context.size.width / 8)
                                           Spacer(minLength: 0)
                                       }
                                   })
            let renderer = ImageRenderer(content: tile)
            renderer.scale = 1
            return try XCTUnwrap(renderer.cgImage)
        }
        func isRed(_ image: CGImage, x: Int, y: Int) throws -> Bool {
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = try XCTUnwrap(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
            return px[0] > 200 && px[1] < 60 && px[2] < 60
        }

        let atFit = Seen()
        XCTAssertTrue(try isRed(try render(MapViewTransform(), seen: atFit), x: 12, y: 60), "the overlay is drawn over the tile")
        let fitContext = try XCTUnwrap(atFit.contexts.last)
        XCTAssertEqual(fitContext.size, size); XCTAssertEqual(fitContext.scanWidth, 40); XCTAssertEqual(fitContext.scanHeight, 20)
        XCTAssertEqual(fitContext.zoom, 1)

        var zoomed = MapViewTransform(); zoomed.zoom(by: 2, about: CGPoint(x: 0.5, y: 0.5))
        let atTwo = Seen()
        XCTAssertFalse(try isRed(try render(zoomed, seen: atTwo), x: 12, y: 60), "the overlay zooms with the picture")
        XCTAssertEqual(try XCTUnwrap(atTwo.contexts.last).zoom, 2)
    }

    /// The tile is the shared viewport: its zoom and pan routes are `ImageViewport`'s, not a second copy of its own. Red under: the
    /// tile's own wheel or pinch back, or the viewport dropped.
    func testTheTileSitsInTheSharedViewport() throws {
        let tile = squeezed(try source("Sources/ShellSpectroscopy/MapTileView.swift"))
        XCTAssertTrue(tile.contains("ImageViewport(zoomModel, box: size"))
        XCTAssertTrue(tile.contains(".zoomPanPlacement(view.paneState(in: size))"), "placed by the live zoom, never below the fit")
        XCTAssertTrue(tile.contains("isCommandTarget: false, publishesCommands: false"), "a focused tile never masks the maps' View > Zoom")
        XCTAssertFalse(tile.contains(".onScrollWheel"), "the wheel is the viewport's")
        XCTAssertFalse(tile.contains("MagnifyGesture"), "the pinch is the viewport's")
        XCTAssertTrue(tile.contains(".zoomPanAccessibilityActions(zoomModel, box: size)"), "VoiceOver's zoom actions sit on the labelled tile")
    }

    /// The EDS room hands the app's overlay to every map tile, by the tile's id. Red under: the hook dropped between the room's
    /// actions and the tile.
    @MainActor func testTheEDSRoomHandsTheAppsOverlayToItsTiles() throws {
        let actions = EDXRoomActions(report: { _ in }, present: { _ in }, mapOverlay: { id, _ in AnyView(Text(id)) })
        XCTAssertNotNil(actions.mapOverlay)
        XCTAssertNil(EDXRoomActions(report: { _ in }, present: { _ in }).mapOverlay, "no overlay unless the app gives one")
        let room = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXRoom.swift"))
        XCTAssertTrue(room.contains("EDXMapsBlock(session: session, state: state, overlay: actions.mapOverlay)"))
        let block = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXMapsBlock.swift"))
        XCTAssertTrue(block.contains("session: session, state: state, overlay: overlay)"))
        XCTAssertTrue(block.contains("if let overlay { overlay(tileID ?? EDXGridItem.mixID, context) }"))
    }
}
