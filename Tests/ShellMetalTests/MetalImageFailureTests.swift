//
//  MetalImageFailureTests.swift
//  An image the GPU cannot hold, or a Metal that did not start, is said on the pane, never a trap or a silent blank (MacEMUI#124).
//  Red before: the engine `fatalError`ed at start-up; an RGBA image past 16384 px a side tried a texture and left the pane blank;
//  a scale-only change rebuilt the image but skipped the redraw; a NaN in a normalised image drew as a colour.
//

import XCTest
import Metal
@testable import ShellMetal

nonisolated final class MetalImageFailureTests: XCTestCase {

    func testTheEngineStartsOrSaysWhy() {
        switch MetalEngine.startup {
        case .success(let engine): XCTAssertTrue(MetalEngine.available === engine)
        case .failure(let error): XCTAssertNil(MetalEngine.available); XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testAnRGBATexturePastTheSideLimitIsNotMadeAndTheFailureIsWorded() throws {
        let engine = try XCTUnwrap(MetalEngine.available)
        let side = MetalImageFailure.maximumTextureSide + 1
        XCTAssertNil(engine.device.makeRGBATexture(rgba: [UInt8](repeating: 0, count: side * 4), width: side, height: 1))
        XCTAssertNil(engine.device.makeRGBATexture(rgba: [0, 0, 0], width: 1, height: 1), "a short buffer is not read past")
        XCTAssertNotNil(engine.device.makeRGBATexture(rgba: [1, 2, 3, 255], width: 1, height: 1))
        XCTAssertTrue(MetalImageFailure.tooLarge(width: side, height: 1).text.contains("\(side) × 1"))
        XCTAssertTrue(MetalImageFailure.noMetal("No Metal-capable GPU was found.").text.contains("Metal did not start"))
    }

    @MainActor func testAScaleOnlyChangeRedraws() {
        let normalized = MetalImageView(pixels: [0, 1], width: 2, height: 1, contentVersion: 7)
        let raw = MetalImageView(pixels: [0, 1], width: 2, height: 1, contentVersion: 7, pixelScale: .raw(range: 0...1))
        XCTAssertNotEqual(normalized.appliedState, raw.appliedState)
        let native = MetalImageView(pixels: [], width: 2, height: 1, contentVersion: 7, pixelScale: .raw(range: 0...1),
                                    nativePixels: .uint8([0, 1]))
        XCTAssertNotEqual(raw.appliedState, native.appliedState)
    }

    @MainActor func testANaNInANormalisedImageDrawsAsMasked() throws {
        let engine = try XCTUnwrap(MetalEngine.available)
        let lut = try XCTUnwrap(engine.device.makeLUTTexture(rgba: Colormaps.lutRGBA(.gray, count: 256)))
        let image = try XCTUnwrap(engine.device.makeImageBuffer(pixels: [.nan, -1, 0.5], width: 3, height: 1))
        let bgra = try Self.render(engine, width: 3, height: 1) { encoder in
            var display = SIMD4<Float>(0, 1, 1, 0)
            encoder.setFragmentBytes(&display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            let d = DisplayImage(buffer: image, width: 3, height: 1, encoding: .normalizedFloat, low: 0, span: 1)
            encoder.setFragmentBuffer(d.buffer, offset: 0, index: 1)
            var size = SIMD2<UInt32>(3, 1)
            encoder.setFragmentBytes(&size, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 2)
            var parameters = d.parameters
            encoder.setFragmentBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
            encoder.setFragmentTexture(lut, index: 1)
        }
        XCTAssertEqual(Array(bgra[0..<4]), Array(bgra[4..<8]), "NaN draws as the masked grey, as a negative value does")
        XCTAssertNotEqual(Array(bgra[0..<4]), Array(bgra[8..<12]))
    }

    private static func render(_ engine: MetalEngine, width: Int, height: Int,
                               bind: (MTLRenderCommandEncoder) -> Void) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
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
        encoder.setRenderPipelineState(engine.displayPSO)
        let identity = MetalDisplayTransform.identity(CGSize(width: width, height: height)).shaderRows()
        var rows = [identity.0, identity.1]
        encoder.setVertexBytes(&rows, length: 2 * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        bind(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return out
    }
}
