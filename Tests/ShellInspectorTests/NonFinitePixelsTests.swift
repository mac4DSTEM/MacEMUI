//
//  NonFinitePixelsTests.swift
//  A pixel count that is not a number or past Int is spoken, never `Int(NaN)` (MacEMUI#124).
//

import XCTest
@testable import ShellInspector

nonisolated final class NonFinitePixelsTests: XCTestCase {
    func testANaNInfiniteOrHugePixelCountIsSpoken() {
        XCTAssertTrue(RoomAccessibilityText.pixels(.nan).hasSuffix("pixels"))
        XCTAssertTrue(RoomAccessibilityText.pixels(.infinity).hasSuffix("pixels"))
        XCTAssertTrue(RoomAccessibilityText.pixels(1e300).hasSuffix("pixels"))
        XCTAssertEqual(RoomAccessibilityText.pixels(12), "12 pixels")
        XCTAssertEqual(RoomAccessibilityText.pixels(1), "1 pixel")
    }
}
