//
//  MTLTextureFloatTests.swift
//  Hygiene audit row 10-lite (2026-09-16): `MTLTexture+Float.swift` had zero
//  test references (code-metrics.md table D2). These round-trip small known
//  arrays through `makeFloatTexture` / `makeRGBATexture` / `makeLUTTexture`
//  and read them back with `getBytes`, asserting exact byte equality — both
//  `.r32Float` and `.rgba8Unorm` store the given bytes without quantization,
//  so a correct round trip is exact, not merely close.
//

import XCTest
import Metal
@testable import ShellMetal

nonisolated final class MTLTextureFloatTests: XCTestCase {

    /// A runner without a usable GPU skips these tests instead of failing them.
    override func setUpWithError() throws {
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
    }

    private func device() throws -> MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    /// A non-square size so a width/height swap in the descriptor or the
    /// upload's `bytesPerRow` would misalign the read-back, not merely
    /// transpose values that happen to look the same.
    func testFloatTextureRoundTripsExactValues() throws {
        let dev = try device()
        let width = 3, height = 2
        let pixels: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0, -0.125]
        let tex = try XCTUnwrap(dev.makeFloatTexture(pixels: pixels, width: width, height: height))

        XCTAssertEqual(tex.width, width)
        XCTAssertEqual(tex.height, height)

        var readBack = [Float](repeating: .nan, count: width * height)
        readBack.withUnsafeMutableBytes { raw in
            tex.getBytes(raw.baseAddress!, bytesPerRow: width * MemoryLayout<Float>.stride,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }

        XCTAssertEqual(readBack, pixels, "r32Float must round-trip float32 bit-exactly")
    }

    /// RGBA bytes with every channel distinct per pixel, so a dropped or
    /// mis-strided channel changes a value rather than silently matching.
    func testRGBATextureRoundTripsExactBytes() throws {
        let dev = try device()
        let width = 2, height = 2
        // 4 pixels × (r,g,b,a), each channel a different value so a channel
        // swap or drop is visible in the comparison.
        let rgba: [UInt8] = [
            10, 20, 30, 255,
            40, 50, 60, 128,
            70, 80, 90, 64,
            100, 110, 120, 0,
        ]
        let tex = try XCTUnwrap(dev.makeRGBATexture(rgba: rgba, width: width, height: height))

        XCTAssertEqual(tex.width, width)
        XCTAssertEqual(tex.height, height)

        var readBack = [UInt8](repeating: 0xFF, count: rgba.count)
        readBack.withUnsafeMutableBytes { raw in
            tex.getBytes(raw.baseAddress!, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }

        XCTAssertEqual(readBack, rgba, "rgba8Unorm must round-trip the exact bytes written")
    }

    /// A 1D LUT with a known length distinct from any padding the texture
    /// might otherwise silently apply — an off-by-one in the region used to
    /// build OR read the texture drops or shifts an entry.
    func testLUTTextureRoundTripsExactBytes() throws {
        let dev = try device()
        let entries = 5
        var rgba = [UInt8]()
        rgba.reserveCapacity(entries * 4)
        for i in 0..<entries {
            let base = UInt8(i * 10)
            rgba.append(contentsOf: [base, base &+ 1, base &+ 2, base &+ 3])
        }
        let tex = try XCTUnwrap(dev.makeLUTTexture(rgba: rgba))

        XCTAssertEqual(tex.width, entries)

        var readBack = [UInt8](repeating: 0xFF, count: rgba.count)
        readBack.withUnsafeMutableBytes { raw in
            tex.getBytes(raw.baseAddress!, bytesPerRow: entries * 4,
                         from: MTLRegionMake1D(0, entries), mipmapLevel: 0)
        }

        XCTAssertEqual(readBack, rgba, "the 1D LUT must round-trip every entry, none dropped or shifted")
    }
}
