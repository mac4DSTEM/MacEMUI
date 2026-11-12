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

    /// The GPU image for raw pixels at the narrowest width that holds them exactly: whole numbers in 0…255 as one byte each,
    /// in 0…65535 as two, which the shader normalises over `range` as it draws (`DisplayImage.Encoding`); anything else (a
    /// fraction, a negative or non-finite value) as Float32 normalised here (`makeNormalizedImageBuffer`). An 8-bit SEM
    /// image then costs one byte a pixel on the GPU, as ImageJ, GMS and Velox keep it, not four (macTEM#562). The picture
    /// is the same: the shader's `(v - low) / span` is the CPU's to within the GPU's float division, far below one LUT step.
    func makeDisplayImage(raw: [Float], width: Int, height: Int, range: ClosedRange<Float>?) -> DisplayImage? {
        guard width > 0, height > 0, raw.count == width * height else { return nil }
        if let range, range.lowerBound >= 0, range.upperBound <= 65_535 {
            let narrow = range.upperBound <= 255
            if let buffer = narrow ? packed(raw, as: UInt8.self) : packed(raw, as: UInt16.self) {
                return DisplayImage(buffer: buffer, width: width, height: height, encoding: narrow ? .uint8 : .uint16,
                                    low: range.lowerBound, span: range.upperBound - range.lowerBound)
            }
        }
        return makeNormalizedImageBuffer(raw: raw, width: width, height: height, range: range).map {
            DisplayImage(buffer: $0, width: width, height: height, encoding: .normalizedFloat, low: 0, span: 1)
        }
    }

    /// The GPU image of pixels kept at their own bit depth: the bytes as they are, normalised by the shader over `range` (the
    /// range of these values; nil, which whole numbers never have, draws them all at 0).
    func makeDisplayImage(native: MetalImageView.NativePixels, width: Int, height: Int,
                          range: ClosedRange<Float>?) -> DisplayImage? {
        guard width > 0, height > 0, native.count == width * height else { return nil }
        let buffer: MTLBuffer?
        let encoding: DisplayImage.Encoding
        switch native {
        case .uint8(let values):
            encoding = .uint8
            buffer = values.withUnsafeBytes { makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        case .uint16(let values):
            encoding = .uint16
            buffer = values.withUnsafeBytes { makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        }
        let low = range?.lowerBound ?? 0
        return buffer.map { DisplayImage(buffer: $0, width: width, height: height, encoding: encoding, low: low,
                                         span: (range?.upperBound ?? low) - low) }
    }

    /// `raw` as `T`, or nil at the first value `T` does not hold exactly (a fraction, out of range, non-finite).
    private func packed<T: FixedWidthInteger & UnsignedInteger>(_ raw: [Float], as _: T.Type) -> MTLBuffer? {
        guard let buffer = makeBuffer(length: max(raw.count * MemoryLayout<T>.stride, 1), options: .storageModeShared) else { return nil }
        let out = buffer.contents().bindMemory(to: T.self, capacity: raw.count)
        let top = Float(T.max)
        let exact = raw.withUnsafeBufferPointer { source -> Bool in
            for i in 0..<source.count {
                let v = source[i]
                guard v >= 0, v <= top, v.rounded(.towardZero) == v else { return false }   // NaN fails `v >= 0`
                out[i] = T(v)
            }
            return true
        }
        return exact ? buffer : nil
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

/// The scalar image `colormapFragment` reads: the buffer, its size and how its values are stored.
nonisolated struct DisplayImage: @unchecked Sendable {   // DEVIATION: an MTLBuffer is safe to hand between threads once written
    enum Encoding: UInt32 {
        /// Float32 display values, [0, 1] or negative for masked.
        case normalizedFloat = 0
        /// Whole-number raw values, normalised by the shader over `low` and `span`.
        case uint8 = 1
        case uint16 = 2
    }
    let buffer: MTLBuffer
    let width: Int
    let height: Int
    let encoding: Encoding
    let low: Float
    let span: Float

    /// The shader's image parameters: (low, span, encoding, 0).
    var parameters: SIMD4<Float> { SIMD4<Float>(low, span, Float(encoding.rawValue), 0) }
}
