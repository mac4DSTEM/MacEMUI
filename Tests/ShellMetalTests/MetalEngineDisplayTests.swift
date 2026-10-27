// MOVED FROM: macTEM@51c944c macTEMTests/MetalEngineDisplayTests.swift (mac4DSTEM had no counterpart)
// Changes: imports ShellMetal (@testable); the engine's library is the package's `default.metallib` (`Bundle.module`), not the test host's; `FloatImage.invalidDisplayValue` is the literal -1; assertions unchanged.
// END MOVED FROM
//
//  MetalEngineDisplayTests.swift
//  Pins `MetalEngine.shared`: it builds both display pipelines from the package's own default.metallib, and each pipeline draws what MetalImageView relies on. Off screen,
//  one pixel per texel: the scalar pipeline maps 0 and 1 to the gray LUT's ends and the masked sentinel to its
//  neutral gray, and draws the image's row 0 at the TOP (as GMS, ncempy and RosettaSciIO show it); the RGBA
//  pipeline draws its texture's bytes unchanged.
//

import XCTest
import Metal
@testable import ShellMetal

nonisolated final class MetalEngineDisplayTests: XCTestCase {

    /// A runner without a usable GPU skips these tests: `MetalEngine.shared` stops the process without a device.
    override func setUpWithError() throws {
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
    }

    func testTheEngineBuildsFromThePackagesDefaultLibrary() throws {
        let engine = MetalEngine.shared
        let names = Set(engine.library.functionNames)
        XCTAssertTrue(names.isSuperset(of: ["displayVertex", "colormapFragment", "rgbaFragment"]), "\(names.sorted())")
        XCTAssertEqual(engine.displayPSO.device.registryID, engine.device.registryID)
        XCTAssertEqual(engine.displayRGBAPSO.device.registryID, engine.device.registryID)
        XCTAssertFalse(engine.device.name.isEmpty)
    }

    @MainActor func testTheScalarPipelineDrawsTheGrayLUTEndsAndTheMaskedGray() throws {
        let engine = MetalEngine.shared
        let data = try XCTUnwrap(engine.device.makeFloatTexture(
            pixels: [0, 1, -1 /* FloatImage.invalidDisplayValue */], width: 3, height: 1))
        let lut = try XCTUnwrap(engine.device.makeLUTTexture(rgba: Colormaps.lutRGBA(.gray, count: 256)))
        let bgra = try Self.render(engine.displayPSO, width: 3, height: 1) { encoder in
            var display = SIMD4<Float>(0, 1, 1, 0)                     // lo, hi, gamma: the full range, linear
            encoder.setFragmentBytes(&display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setFragmentTexture(data, index: 0)
            encoder.setFragmentTexture(lut, index: 1)
        }
        XCTAssertEqual(Array(bgra[0..<4]), [0, 0, 0, 255], "0 is the LUT's first entry")
        XCTAssertEqual(Array(bgra[4..<8]), [255, 255, 255, 255], "1 is the LUT's last entry")
        // The masked colour (0.32, 0.32, 0.34): B 86.7, G 81.6, R 81.6 before the unorm conversion rounds.
        for (channel, want) in zip(bgra[8..<11], [87, 82, 82] as [Int]) {
            XCTAssertLessThanOrEqual(abs(Int(channel) - want), 1, "masked pixel \(Array(bgra[8..<12]))")
        }
        XCTAssertEqual(bgra[11], 255)
    }

    /// A 1 × 2 image, row 0 black and row 1 white: the target's first row (Metal's texture origin is the top-left)
    /// must be black. The shader's flipped v is what puts it there; unflipped, the image is drawn upside down.
    @MainActor func testRowZeroOfTheImageIsDrawnAtTheTop() throws {
        let engine = MetalEngine.shared
        let data = try XCTUnwrap(engine.device.makeFloatTexture(pixels: [0, 1], width: 1, height: 2))
        let lut = try XCTUnwrap(engine.device.makeLUTTexture(rgba: Colormaps.lutRGBA(.gray, count: 256)))
        let bgra = try Self.render(engine.displayPSO, width: 1, height: 2) { encoder in
            var display = SIMD4<Float>(0, 1, 1, 0)
            encoder.setFragmentBytes(&display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setFragmentTexture(data, index: 0)
            encoder.setFragmentTexture(lut, index: 1)
        }
        XCTAssertEqual(Array(bgra[0..<4]), [0, 0, 0, 255], "the top row is the image's row 0")
        XCTAssertEqual(Array(bgra[4..<8]), [255, 255, 255, 255], "the bottom row is its last row")
    }

    func testTheRGBAPipelineDrawsItsTextureUnchanged() throws {
        let engine = MetalEngine.shared
        let rgba: [UInt8] = [10, 20, 30, 255, 200, 150, 100, 255]
        let texture = try XCTUnwrap(engine.device.makeRGBATexture(rgba: rgba, width: 2, height: 1))
        let bgra = try Self.render(engine.displayRGBAPSO, width: 2, height: 1) { encoder in
            encoder.setFragmentTexture(texture, index: 0)
        }
        XCTAssertEqual(bgra, [30, 20, 10, 255, 100, 150, 200, 255], "BGRA of the RGBA given, column for column")
    }

    /// One frame of `pso` into a `width` × `height` BGRA8 target, the identity transform MetalImageView passes, read
    /// back. The clear colour is magenta, so a pixel the draw missed cannot pass for black or white.
    private static func render(_ pso: MTLRenderPipelineState, width: Int, height: Int,
                               bind: (MTLRenderCommandEncoder) -> Void) throws -> [UInt8] {
        let engine = MetalEngine.shared
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let target = try XCTUnwrap(engine.device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 1, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        let buffer = try XCTUnwrap(engine.queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(buffer.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pso)
        // The two rows MetalImageView passes for the identity (whole image over the view), from the same type.
        let identity = MetalDisplayTransform.identity(CGSize(width: width, height: height)).shaderRows()
        var rows = [identity.0, identity.1]
        encoder.setVertexBytes(&rows, length: 2 * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        bind(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        XCTAssertEqual(buffer.status, .completed, "\(String(describing: buffer.error))")
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return out
    }
}
