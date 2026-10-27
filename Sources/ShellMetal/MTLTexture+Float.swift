//
//  MTLTexture+Float.swift
//  Role: Small helpers to turn Swift arrays into Metal textures used by the
//        display pipeline: a single-channel r32Float image texture, and a 1D
//        rgba8 colormap LUT texture.
//

import Metal

nonisolated extension MTLDevice {

    /// Build an `.r32Float` 2D texture from normalized [0,1] float pixels
    /// (row-major, length == width*height). Sampled by colormapFragment.
    func makeFloatTexture(pixels: [Float], width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = makeTexture(descriptor: desc) else { return nil }
        pixels.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: width * MemoryLayout<Float>.stride)
        }
        return tex
    }

    /// Build an `.rgba8Unorm` 2D texture from packed RGBA bytes
    /// (row-major, length == width*height*4). Sampled by rgbaFragment.
    func makeRGBATexture(rgba: [UInt8], width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = makeTexture(descriptor: desc) else { return nil }
        rgba.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: width * 4)
        }
        return tex
    }

    /// Build a 1D `.rgba8Unorm` colormap LUT texture from 256*4 bytes.
    func makeLUTTexture(rgba: [UInt8]) -> MTLTexture? {
        let count = rgba.count / 4
        let desc = MTLTextureDescriptor()
        desc.textureType = .type1D
        desc.pixelFormat = .rgba8Unorm
        desc.width = count
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = makeTexture(descriptor: desc) else { return nil }
        rgba.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake1D(0, count),
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: count * 4)
        }
        return tex
    }
}
