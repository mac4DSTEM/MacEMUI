//
//  MTLTextureFloatTests.swift
//  Hygiene audit row 10-lite (2026-09-16): `MTLTexture+Float.swift` had zero
//  test references (code-metrics.md table D2). These round-trip small known
//  arrays through `makeImageBuffer` / `makeRGBATexture` / `makeLUTTexture`
//  and read them back, asserting exact equality — the Float32 buffer and
//  `.rgba8Unorm` store the given bytes without quantization, so a correct
//  round trip is exact, not merely close.
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

    /// The image buffer holds the pixels exactly, in row-major order, and refuses a count that is not width × height.
    func testImageBufferHoldsExactValues() throws {
        let dev = try device()
        let pixels: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0, -0.125]
        let buffer = try XCTUnwrap(dev.makeImageBuffer(pixels: pixels, width: 3, height: 2))
        XCTAssertEqual(contents(buffer, count: 6), pixels)
        XCTAssertNil(dev.makeImageBuffer(pixels: pixels, width: 4, height: 2))
    }

    private func contents(_ buffer: MTLBuffer, count: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: Float.self, capacity: count), count: count))
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

    /// The raw path builds the buffer `makeImageBuffer` builds from the normalised copy, bit for bit, with non-finite values
    /// masked, and the flat and empty ranges as the normalisation defines them.
    func testNormalizedImageBufferFromRawEqualsTheNormalisedCopysBuffer() throws {
        let dev = try device()
        let width = 3, height = 5
        let raw: [Float] = [3, 7, 11, 2, .nan, 19, 23, -4, 0.5, 8, .infinity, 13, 1, 6, 17]
        let finite = raw.filter(\.isFinite)
        let low = try XCTUnwrap(finite.min()), high = try XCTUnwrap(finite.max())
        func reference(_ low: Float, _ span: Float) -> [Float] {
            raw.map { $0.isFinite ? (span > 0 ? ($0 - low) / span : 0) : -1 }
        }
        let made = try XCTUnwrap(dev.makeNormalizedImageBuffer(raw: raw, width: width, height: height, range: low...high))
        let expected = try XCTUnwrap(dev.makeImageBuffer(pixels: reference(low, high - low), width: width, height: height))
        XCTAssertEqual(contents(made, count: raw.count).map(\.bitPattern), contents(expected, count: raw.count).map(\.bitPattern))
        let flat = try XCTUnwrap(dev.makeNormalizedImageBuffer(raw: raw, width: width, height: height, range: 5...5))
        XCTAssertEqual(contents(flat, count: raw.count), reference(5, 0))
        let none = try XCTUnwrap(dev.makeNormalizedImageBuffer(raw: raw, width: width, height: height, range: nil))
        XCTAssertEqual(contents(none, count: raw.count), [Float](repeating: -1, count: raw.count))
        XCTAssertNil(dev.makeNormalizedImageBuffer(raw: raw, width: width, height: height + 1, range: low...high))
    }

    /// Raw pixels keep the narrowest width that holds them exactly: whole numbers in 0…255 one byte each, in 0…65535 two,
    /// anything else Float32 display values. The bytes are the values themselves.
    func testTheDisplayImageKeepsWholeNumbersAtTheirOwnWidth() throws {
        let dev = try device()
        let bytes = try XCTUnwrap(dev.makeDisplayImage(raw: [0, 17, 255, 3], width: 2, height: 2, range: 0...255))
        XCTAssertEqual(bytes.encoding, .uint8)
        XCTAssertEqual(bytes.buffer.length, 4)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes.buffer.contents().bindMemory(to: UInt8.self, capacity: 4), count: 4)), [0, 17, 255, 3])
        XCTAssertEqual(bytes.parameters, SIMD4<Float>(0, 255, 1, 0))
        let words = try XCTUnwrap(dev.makeDisplayImage(raw: [100, 65_535, 300, 100], width: 2, height: 2, range: 100...65_535))
        XCTAssertEqual(words.encoding, .uint16)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: words.buffer.contents().bindMemory(to: UInt16.self, capacity: 4), count: 4)), [100, 65_535, 300, 100])
        XCTAssertEqual(words.parameters, SIMD4<Float>(100, 65_435, 2, 0))
        for (raw, range) in [([0, 0.5, 1, 2], 0...2), ([-1, 0, 1, 2], -1...2), ([0, .nan, 1, 2], 0...2), ([0, 1, 2, 70_000], 0...70_000)] as [([Float], ClosedRange<Float>)] {
            let image = try XCTUnwrap(dev.makeDisplayImage(raw: raw, width: 2, height: 2, range: range))
            XCTAssertEqual(image.encoding, .normalizedFloat, "\(raw)")
            let expected = try XCTUnwrap(dev.makeNormalizedImageBuffer(raw: raw, width: 2, height: 2, range: range))
            XCTAssertEqual(contents(image.buffer, count: 4).map(\.bitPattern), contents(expected, count: 4).map(\.bitPattern))
        }
        let masked = try XCTUnwrap(dev.makeDisplayImage(raw: [.nan, .nan], width: 2, height: 1, range: nil))
        XCTAssertEqual(contents(masked.buffer, count: 2), [-1, -1])
    }

    /// Native pixels reach the GPU as their own bytes, and give the same image the Float32 values of the same numbers give.
    func testNativePixelsAreTheSameDisplayImageAsTheirFloatValues() throws {
        let dev = try device()
        let bytes: [UInt8] = [0, 17, 255, 3]
        let native = try XCTUnwrap(dev.makeDisplayImage(native: .uint8(bytes), width: 2, height: 2, range: 0...255))
        let viaFloat = try XCTUnwrap(dev.makeDisplayImage(raw: bytes.map(Float.init), width: 2, height: 2, range: 0...255))
        XCTAssertEqual(native.encoding, viaFloat.encoding)
        XCTAssertEqual(native.parameters, viaFloat.parameters)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: native.buffer.contents().bindMemory(to: UInt8.self, capacity: 4), count: 4)), bytes)
        let words: [UInt16] = [100, 65_535, 300, 100]
        let native16 = try XCTUnwrap(dev.makeDisplayImage(native: .uint16(words), width: 2, height: 2, range: 100...65_535))
        XCTAssertEqual(native16.encoding, .uint16)
        XCTAssertEqual(native16.parameters, SIMD4<Float>(100, 65_435, 2, 0))
        XCTAssertNil(dev.makeDisplayImage(native: .uint8(bytes), width: 3, height: 2, range: 0...255))
    }
}
