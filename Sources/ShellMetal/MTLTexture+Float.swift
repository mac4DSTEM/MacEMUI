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

    /// Build the same `.r32Float` texture as `makeFloatTexture(pixels:)` would from the linearly normalised copy of `raw`, without
    /// that copy: the rows are normalised a strip at a time into a small buffer and uploaded, so the caller keeps only its raw
    /// pixels (a 19433 × 19320 image held three full-size Float32 copies, 4.4 GB, measured 2026-11-12, macTEM#562).
    ///
    /// The normalisation is ImagoKit's `DisplayNormalization.normalized` (linear, not symmetric), value for value: a finite value
    /// `v` becomes `(v - low) / (high - low)` in Float32, a non-finite one `invalidValue` (the masked sentinel); when
    /// `high - low` is not positive every finite value becomes 0. `range` is the finite raw range the caller already holds
    /// (`CanvasPixels.rawRange`); nil, as for an image with no finite value, draws every pixel masked.
    func makeNormalizedTexture(raw: [Float], width: Int, height: Int, range: ClosedRange<Float>?,
                               invalidValue: Float = -1, stripRows: Int = 256) -> MTLTexture? {
        guard width > 0, height > 0, raw.count == width * height else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = makeTexture(descriptor: desc) else { return nil }
        let low = range?.lowerBound ?? 0
        let span = (range?.upperBound ?? 0) - low
        let rows = max(1, stripRows)
        var strip = [Float](repeating: 0, count: width * min(rows, height))
        raw.withUnsafeBufferPointer { source in
            var row = 0
            while row < height {
                let count = min(rows, height - row)
                let base = row * width
                for i in 0..<(count * width) {
                    let v = source[base + i]
                    strip[i] = range == nil || !v.isFinite ? invalidValue : (span > 0 ? (v - low) / span : 0)
                }
                strip.withUnsafeBytes { bytes in
                    tex.replace(region: MTLRegionMake2D(0, row, width, count), mipmapLevel: 0,
                                withBytes: bytes.baseAddress!, bytesPerRow: width * MemoryLayout<Float>.stride)
                }
                row += count
            }
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
