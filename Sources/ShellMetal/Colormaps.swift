import SwiftUI
import Foundation

/// Anchor colours from matplotlib's viridis and inferno (CC0) and ColorBrewer's RdBu (Apache-2.0); see `NOTICE`.
public nonisolated enum Colormaps {
    /// Returns RGBA bytes for the requested colormap.
    public static func lutRGBA(_ kind: ColormapKind, count: Int = 256) -> [UInt8] {
        let stops = anchors(for: kind)
        var output = [UInt8](repeating: 255, count: count * 4)

        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            let (r, g, b) = sample(stops, at: t)
            output[index * 4 + 0] = UInt8((r * 255).rounded().clamped(0, 255))
            output[index * 4 + 1] = UInt8((g * 255).rounded().clamped(0, 255))
            output[index * 4 + 2] = UInt8((b * 255).rounded().clamped(0, 255))
            output[index * 4 + 3] = 255
        }

        return output
    }

    /// The colour the Metal sampler returns for a normalised value `v` (after window and gamma)
    /// on the 256-texel LUT: linear filter, clamp-to-edge, so texel centres sit at (i + 0.5) / 256.
    /// Matches Colormaps.metal's sampler so an export equals the screen. `lut` is RGBA, 256 texels.
    public static func sampleRGB(_ lut: [UInt8], _ v: Double) -> (UInt8, UInt8, UInt8) {
        let p = min(max(v * 256 - 0.5, 0), 255)
        let i0 = Int(p.rounded(.down))
        let i1 = min(i0 + 1, 255)
        let t = p - Double(i0)
        func channel(_ c: Int) -> UInt8 {
            let a = Double(lut[i0 * 4 + c]), b = Double(lut[i1 * 4 + c])
            return UInt8(Swift.min(Swift.max((a + (b - a) * t).rounded(), 0), 255))
        }
        return (channel(0), channel(1), channel(2))
    }

    private static func sample(
        _ stops: [(Double, Double, Double, Double)],
        at t: Double
    ) -> (Double, Double, Double) {
        if t <= stops.first!.0 {
            let stop = stops.first!
            return (stop.1, stop.2, stop.3)
        }

        if t >= stops.last!.0 {
            let stop = stops.last!
            return (stop.1, stop.2, stop.3)
        }

        for index in 1..<stops.count {
            let start = stops[index - 1]
            let end = stops[index]

            if t <= end.0 {
                let fraction = (t - start.0) / (end.0 - start.0)
                return (
                    start.1 + (end.1 - start.1) * fraction,
                    start.2 + (end.2 - start.2) * fraction,
                    start.3 + (end.3 - start.3) * fraction
                )
            }
        }

        return (1, 1, 1)
    }

    private static func anchors(for kind: ColormapKind) -> [(Double, Double, Double, Double)] {
        switch kind {
        case .gray:
            return [(0, 0, 0, 0), (1, 1, 1, 1)]
        case .viridis:
            return [
                (0.00, 0.267, 0.005, 0.329),
                (0.25, 0.254, 0.265, 0.530),
                (0.50, 0.128, 0.567, 0.551),
                (0.75, 0.369, 0.789, 0.383),
                (1.00, 0.993, 0.906, 0.144)
            ]
        case .inferno:
            return [
                (0.00, 0.001, 0.000, 0.014),
                (0.25, 0.258, 0.039, 0.406),
                (0.50, 0.578, 0.148, 0.404),
                (0.75, 0.865, 0.316, 0.226),
                (0.90, 0.988, 0.645, 0.040),
                (1.00, 0.988, 0.998, 0.645)
            ]
        case .rdbu:
            return [
                (0.00, 0.129, 0.400, 0.674),
                (0.50, 0.969, 0.969, 0.969),
                (1.00, 0.698, 0.094, 0.168)
            ]
        }
    }
}

private nonisolated extension Double {
    func clamped(_ lowerBound: Double, _ upperBound: Double) -> Double {
        Swift.min(Swift.max(self, lowerBound), upperBound)
    }
}

nonisolated extension Colormaps {
    /// Swatch size in points (and pixels at 1x).
    static let swatchWidth = 44
    static let swatchHeight = 12

    /// RGBA bytes of the swatch, row-major: column `x` is the LUT entry at
    /// `x` (left = first colour), repeated down every row. Pure, so a test
    /// can pin the ends and the middle against `lutRGBA`.
    static func swatchRGBA(_ kind: ColormapKind) -> [UInt8] {
        let lut = lutRGBA(kind, count: swatchWidth)
        var bytes = [UInt8](repeating: 255, count: swatchWidth * swatchHeight * 4)
        for y in 0..<swatchHeight {
            for x in 0..<swatchWidth {
                let source = x * 4
                let target = (y * swatchWidth + x) * 4
                bytes[target] = lut[source]
                bytes[target + 1] = lut[source + 1]
                bytes[target + 2] = lut[source + 2]
            }
        }
        return bytes
    }

    /// D3 (owner decision): small gradient swatches for the colorbar-chip
    /// menu, built once per colormap from the same LUT the renderer uses —
    /// the menu shows the actual mapping, not a name. Drawn as a CGImage
    /// (no AppKit: owner rule, SwiftUI only), shown pixel-exact with
    /// `.interpolation(.none)` so each column stays one crisp point wide.
    @MainActor private static var swatchCache: [ColormapKind: CGImage] = [:]

    @MainActor public static func swatch(_ kind: ColormapKind) -> Image {
        let image: CGImage
        if let cached = swatchCache[kind] {
            image = cached
        } else {
            image = swatchCGImage(kind)
            swatchCache[kind] = image
        }
        return Image(decorative: image, scale: 1).interpolation(.none)
    }

    /// The swatch as a `CGImage` (sRGB, 8 bits per channel, `swatchRGBA` bytes).
    static func swatchCGImage(_ kind: ColormapKind) -> CGImage {
        guard let provider = CGDataProvider(data: Data(swatchRGBA(kind)) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: swatchWidth, height: swatchHeight,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: swatchWidth * 4,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            preconditionFailure("A \(swatchWidth)x\(swatchHeight) RGBA swatch always builds")
        }
        return image
    }
}
