//
//  EDXFigureRegionsTests.swift
//  The maps PNG draws the regions as the room does: every shown pin and line on the colour mix, in its own colour, hidden
//  ones left out, no outline on the element tiles. On EDXSessionTests' planted two-pixel image, rendered offscreen.
//

import XCTest
import SwiftUI
import ImageIO
import ShellControls
import SpectroCore
import SpectroEDX
@testable import ShellEDXModel
@testable import ShellSpectroscopy

nonisolated final class EDXFigureRegionsTests: XCTestCase {

    /// A polygon inside one scan pixel, from `a` to `b` of it on both axes.
    private func square(inPixel x: Double, _ a: Double = 0.2, _ b: Double = 0.8) -> [PixelPoint] {
        [PixelPoint(x: x + a, y: a), PixelPoint(x: x + b, y: a), PixelPoint(x: x + b, y: b), PixelPoint(x: x + a, y: b)]
    }

    /// The image as sRGB bytes, RGBA, top row first.
    private func bytes(_ image: CGImage) throws -> [UInt8] {
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return px
    }

    /// The image pixels of colour `c` (within 0.05 on each channel), as (x, y) with a top-left origin.
    private func pixels(_ image: CGImage, of c: EDXPinColor) throws -> [(x: Int, y: Int)] {
        let px = try bytes(image)
        var out: [(x: Int, y: Int)] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                if abs(Double(px[i]) / 255 - c.red) < 0.05, abs(Double(px[i + 1]) / 255 - c.green) < 0.05, abs(Double(px[i + 2]) / 255 - c.blue) < 0.05 {
                    out.append((x, y))
                }
            }
        }
        return out
    }

    /// Two shown pins, a hidden pin, a shown line and a hidden line, each in a colour of its own. The figure with the colour mix draws the shown
    /// ones on the mix tile (the grid's first cell: x 16 to 316 points, one picture tall) and nowhere else; the hidden ones nowhere.
    /// Red under: the figure drawing only the selected region (in white), so no pin colour at all; a hidden pin or line drawn; outlines on every tile.
    @MainActor func testTheMapsFigureDrawsThePinsAndLinesTheColourMixShows() async throws {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        XCTAssertFalse(session.shownTiles.isEmpty, "precondition: maps to draw")

        session.drawPolygon(square(inPixel: 0))
        session.drawPolygon(square(inPixel: 1))
        session.drawPolygon(square(inPixel: 0, 0.35, 0.65))
        await session.settled()
        XCTAssertEqual(session.pins.count, 3)
        let shownLine = try XCTUnwrap(session.drawLine(from: PixelPoint(x: 0.1, y: 0.1), to: PixelPoint(x: 1.9, y: 0.1)))
        let hiddenLine = try XCTUnwrap(session.drawLine(from: PixelPoint(x: 0.1, y: 0.9), to: PixelPoint(x: 1.9, y: 0.9)))
        session.selectWholeMap()
        await session.settled()

        let colors = [EDXPinColor(red: 1, green: 0, blue: 0.6), EDXPinColor(red: 0, green: 1, blue: 0.4), EDXPinColor(red: 0.6, green: 0.2, blue: 1)]
        let lineColor = EDXPinColor(red: 1, green: 0.85, blue: 0), hiddenLineColor = EDXPinColor(red: 0.3, green: 0.6, blue: 1)
        for (pin, color) in zip(session.pins, colors) { session.setPinColor(pin.id, color) }
        session.setLineColor(shownLine.id, lineColor)
        session.setLineColor(hiddenLine.id, hiddenLineColor)
        session.setPinVisible(session.pins[2].id, false)
        session.setLineVisible(hiddenLine.id, false)
        await session.settled()

        let mix = session.shownTiles
        let bare = try XCTUnwrap(EDXMapsFigure.cgImage(try XCTUnwrap(session.figureContent(scaleBar: false, regions: false, mix: mix))))
        for c in colors + [lineColor, hiddenLineColor] {
            XCTAssertTrue(try pixels(bare, of: c).isEmpty, "precondition: \(c) is nowhere in the figure without regions")
        }

        let figure = try XCTUnwrap(EDXMapsFigure.cgImage(try XCTUnwrap(session.figureContent(scaleBar: false, regions: true, mix: mix))))
        if let dir = ProcessInfo.processInfo.environment["MACEMUI_SHOT_DIR"] { try Self.writePNG(figure, to: URL(fileURLWithPath: dir).appendingPathComponent("macemui-figure-pinned-regions.png")) }
        // The mix picture at 2x: x 32 to 632 px; 300 points wide at the 2:1 scan, so 300 px tall.
        for (name, c) in [("Region 1", colors[0]), ("Region 2", colors[1]), ("the line", lineColor)] {
            let hits = try pixels(figure, of: c)
            XCTAssertFalse(hits.isEmpty, "\(name) is drawn in its own colour")
            XCTAssertTrue(hits.allSatisfy { $0.x >= 32 && $0.x <= 632 }, "\(name) is drawn on the colour mix only (the first column)")
            let ys = hits.map(\.y)
            XCTAssertLessThan((ys.max() ?? 0) - (ys.min() ?? 0), 300, "\(name) is drawn on one tile, not on the tile below the mix too")
        }
        XCTAssertTrue(try pixels(figure, of: colors[2]).isEmpty, "a hidden pin stays hidden")
        XCTAssertTrue(try pixels(figure, of: hiddenLineColor).isEmpty, "a hidden line stays hidden")
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
