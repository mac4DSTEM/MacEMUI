//
//  EDXMixOutlineTests.swift
//  Pinned regions on the colour mix. The mix is the maps block's anchor tile, the one tile handed the room's regions; every
//  pinned region that is shown is outlined on it in its own colour, the selected one and the others alike. On EDXSessionTests'
//  planted two-pixel image, rendered offscreen with ImageRenderer.
//

import XCTest
import SwiftUI
import ImageIO
import ShellControls
import SpectroCore
import SpectroEDX
@testable import ShellEDXModel
@testable import ShellSpectroscopy

nonisolated final class EDXMixOutlineTests: XCTestCase {

    private static let tileSize = CGSize(width: 200, height: 100)

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// The colour mix tile as the maps block draws it: the room's region set over the anchor tile (no picture: the outlines only).
    @MainActor private func renderMix(_ session: EDXSession, scale: CGFloat = 2) throws -> CGImage {
        let set = EDXRegionBridge.set(session, linesFocused: false)
        let tile = MapTileView(title: "Colour mix", image: nil, size: Self.tileSize, scanWidth: 2, scanHeight: 1,
                               regions: MapTileRegions(set: set, tool: .pointer, onRectangle: { _, _, _, _ in }, onEllipse: { _, _, _, _ in },
                                                       onPolygon: { _ in }, onLine: { _, _ in }, onEdit: { _, _ in }),
                               onHover: { _ in }, controls: { EmptyView() })
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = scale
        return try XCTUnwrap(renderer.cgImage)
    }

    /// The image's sRGB pixel at (x, y), top-left origin, in image pixels.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> (r: Double, g: Double, b: Double) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255)
    }

    /// Whether the outline of a region of colour `c` crosses the image row `y` near column `x` (a few pixels either side: the stroke is 1.5 points wide).
    private func outlined(_ image: CGImage, x: Int, y: Int, in c: RegionColor) throws -> Bool {
        for dx in -3...3 {
            let p = try pixel(image, x + dx, y)
            if abs(p.r - c.red) < 0.12, abs(p.g - c.green) < 0.12, abs(p.b - c.blue) < 0.12 { return true }
        }
        return false
    }

    /// A polygon inside one scan pixel (it holds that pixel's centre), as the polygon tool would hand it over.
    private func square(inPixel x: Double) -> [PixelPoint] {
        [PixelPoint(x: x + 0.2, y: 0.2), PixelPoint(x: x + 0.8, y: 0.2), PixelPoint(x: x + 0.8, y: 0.8), PixelPoint(x: x + 0.2, y: 0.8)]
    }

    /// Two pinned regions, the second selected: both are outlined on the colour mix in their own colours, the one not selected too. A
    /// hidden pin is not drawn; shown again, it is. The mix is the tile handed the regions (the anchor), and no other tile is.
    /// Red under: the mix drawing the selected region only; a hidden pin drawn; the regions handed to an element tile instead of the mix.
    @MainActor func testPinnedRegionsAreOutlinedOnTheColourMix() async throws {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        session.drawPolygon(square(inPixel: 0))
        session.drawPolygon(square(inPixel: 1))
        await session.settled()
        XCTAssertEqual(session.pins.map(\.name), ["Region 1", "Region 2"])
        let (first, second) = (session.pins[0], session.pins[1])
        XCTAssertEqual(session.selectedPin?.id, second.id, "the last drawn is the selected one")
        let firstColor = EDXRegionBridge.color(first.color, number: first.number), secondColor = EDXRegionBridge.color(second.color, number: second.number)
        XCTAssertNotEqual(firstColor, secondColor, "precondition: two colours to tell the outlines apart")

        // The polygons' vertical edges, half way down the tile, in image pixels at 2x: Region 1 at x 0.8 of the scan (160 px), Region 2 at x 1.2 (240 px).
        let mix = try renderMix(session)
        if let dir = ProcessInfo.processInfo.environment["MACEMUI_SHOT_DIR"] { try Self.writePNG(mix, to: URL(fileURLWithPath: dir).appendingPathComponent("macemui-mix-pinned-outlines.png")) }
        XCTAssertTrue(try outlined(mix, x: 160, y: 100, in: firstColor), "the pinned region that is not selected is outlined on the mix")
        XCTAssertTrue(try outlined(mix, x: 240, y: 100, in: secondColor), "the selected pinned region is outlined on the mix")

        session.setPinVisible(first.id, false)
        let hidden = try renderMix(session)
        XCTAssertFalse(try outlined(hidden, x: 160, y: 100, in: firstColor), "a hidden pin is not drawn")
        XCTAssertTrue(try outlined(hidden, x: 240, y: 100, in: secondColor))
        session.setPinVisible(first.id, true)
        XCTAssertTrue(try outlined(try renderMix(session), x: 160, y: 100, in: firstColor), "shown again, it is drawn again")

        // The mix is the anchor, and only the anchor tile is handed the regions.
        let composition = EDXMapsComposition.items(scan: [10, 20], tiles: [], appearance: MapAppearance())
        XCTAssertEqual(composition.anchor?.id, EDXGridItem.mixID)
        let block = squeezed(try source("Sources/ShellSpectroscopy/EDX/EDXMapsBlock.swift"))
        XCTAssertTrue(block.contains("regions: isAnchor ? regions : nil"), "the regions go to the anchor tile only")
        XCTAssertTrue(block.contains("let regions = EDXRegionBridge.set(session, linesFocused: state.linesFocused)"), "every pin, not only the selected one")
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
