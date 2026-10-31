import ShellMetal
import XCTest
@testable import ShellControls

/// MacEMUI#44: the colourbar strip is the same colour function the Metal view draws the image with, a linear
/// filter over the LUT texture, not the nearest LUT entry.
nonisolated final class ColorbarStripTests: XCTestCase {
    /// Two entries, black then white: halfway between their texel centres the strip is mid gray.
    private let twoEntries: [UInt8] = [0, 0, 0, 255, 255, 255, 255, 255]

    func testHalfwayBetweenTwoEntriesIsTheirMean() {
        // Texel centres sit at 0.25 and 0.75; 0.5 is halfway.
        let mid = Colorbar.stripRGB(twoEntries, at: 0.5)
        XCTAssertEqual(mid.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(mid.y, 0.5, accuracy: 1e-6)
        XCTAssertEqual(mid.z, 0.5, accuracy: 1e-6)
        let quarterWay = Colorbar.stripRGB(twoEntries, at: 0.375)
        XCTAssertEqual(quarterWay.x, 0.25, accuracy: 1e-6)
    }

    func testTheEndsClampToTheFirstAndLastEntryLikeTheImage() {
        XCTAssertEqual(Colorbar.stripRGB(twoEntries, at: 0), SIMD3(0, 0, 0))
        XCTAssertEqual(Colorbar.stripRGB(twoEntries, at: 0.2), SIMD3(0, 0, 0))
        XCTAssertEqual(Colorbar.stripRGB(twoEntries, at: 1), SIMD3(1, 1, 1))
        XCTAssertEqual(Colorbar.stripRGB(twoEntries, at: 0.9), SIMD3(1, 1, 1))
    }

    /// On the real 256-entry LUT the image uses, halfway between entries 100 and 101 is their mean.
    func testOnTheImageLUTAPositionBetweenEntriesIsTheirMean() {
        let lut = Colormaps.lutRGBA(.viridis, count: 256)
        let rgb = Colorbar.stripRGB(lut, at: Float(101) / 256)
        for channel in 0..<3 {
            let mean = (Double(lut[100 * 4 + channel]) + Double(lut[101 * 4 + channel])) / 2 / 255
            XCTAssertEqual(rgb[channel], mean, accuracy: 1e-6)
        }
    }
}
