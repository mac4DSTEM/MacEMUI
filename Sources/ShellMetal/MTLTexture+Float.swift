//
//  MTLTexture+Float.swift
//  Role: Small helpers to turn Swift arrays into the Metal resources the
//        display pipeline draws: a Float32 image buffer, an rgba8 texture, and a
//        1D rgba8 colormap LUT texture.
//

import Metal

nonisolated extension MTLDevice {

    /// The scalar image the display draws, as a shared Float32 buffer (row-major, `width` × `height`) read by
    /// `colormapFragment` with nearest-pixel indexing. A buffer, not an `.r32Float` texture: a texture is limited to 16384
    /// pixels a side on Apple GPUs, and a 19433 × 19320 SEM TIFF must draw (macTEM#562); a buffer is limited only by
    /// `maxBufferLength`. The pixels are drawn exactly as given (normalised [0, 1], negative = masked).
    func makeImageBuffer(pixels: [Float], width: Int, height: Int) -> MTLBuffer? {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        return pixels.withUnsafeBytes { bytes in
            makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
    }

    /// The buffer `makeImageBuffer(pixels:)` would make from the linearly normalised copy of `raw`, without that copy: each
    /// value is normalised straight into the buffer, so the caller keeps only its raw pixels (a 19433 × 19320 image held three
    /// full-size Float32 copies, 4.4 GB, measured 2026-11-12, macTEM#562).
    ///
    /// The normalisation is ImagoKit's `DisplayNormalization.normalized` (linear, not symmetric), value for value: a finite value
    /// `v` becomes `(v - low) / (high - low)` in Float32, a non-finite one `invalidValue` (the masked sentinel); when
    /// `high - low` is not positive every finite value becomes 0. `range` is the finite raw range the caller already holds
    /// (macTEM's `CanvasPixels.rawRange`); nil, as for an image with no finite value, draws every pixel masked.
    func makeNormalizedImageBuffer(raw: [Float], width: Int, height: Int, range: ClosedRange<Float>?,
                                   invalidValue: Float = -1) -> MTLBuffer? {
        guard width > 0, height > 0, raw.count == width * height,
              let buffer = makeBuffer(length: raw.count * MemoryLayout<Float>.stride, options: .storageModeShared)
        else { return nil }
        let out = buffer.contents().bindMemory(to: Float.self, capacity: raw.count)
        let low = range?.lowerBound ?? 0
        let span = (range?.upperBound ?? 0) - low
        raw.withUnsafeBufferPointer { source in
            for i in 0..<source.count {
                let v = source[i]
                out[i] = range == nil || !v.isFinite ? invalidValue : (span > 0 ? (v - low) / span : 0)
            }
        }
        return buffer
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
