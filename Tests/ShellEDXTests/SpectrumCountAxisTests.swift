//
//  SpectrumCountAxisTests.swift
//  The EDS spectrum's count axis: round ticks and labels that fit the margin. Seen on a Velox map with 14 million counts in
//  its tallest channel: ticks at "3 617 202", "7 234 404", ... with the first digit cut off on the left.
//

import XCTest
@testable import ShellSpectroscopy

nonisolated final class SpectrumCountAxisTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    func testTheCountTicksAreRound() {
        XCTAssertEqual(EDXSpectrumWindow.ticks(in: 0...4776), [0, 1000, 2000, 3000, 4000])
        XCTAssertEqual(EDXSpectrumWindow.ticks(in: 0...14_468_807), [0, 5_000_000, 10_000_000])
        XCTAssertEqual(EDXSpectrumWindow.ticks(in: 0...37), [0, 10, 20, 30])
    }

    func testAxisLabelsFitTheirMargin() {
        XCTAssertEqual(EDXRoomFormat.axisCounts(0, step: 5_000_000, locale: us), "0")
        XCTAssertEqual(EDXRoomFormat.axisCounts(10_000_000, step: 5_000_000, locale: us), "10\u{2009}M")
        XCTAssertEqual(EDXRoomFormat.axisCounts(2_500_000, step: 500_000, locale: us), "2.5\u{2009}M")
        XCTAssertEqual(EDXRoomFormat.axisCounts(500_000, step: 500_000, locale: us), "500\u{2009}k")
        XCTAssertEqual(EDXRoomFormat.axisCounts(150_000, step: 50_000, locale: us), "150\u{2009}k")
        XCTAssertEqual(EDXRoomFormat.axisCounts(4000, step: 1000, locale: us), "4\u{2009}000")
        XCTAssertEqual(EDXRoomFormat.axisCounts(2.5e6, step: 500_000, locale: Locale(identifier: "de_DE")), "2,5\u{2009}M")
        for (v, step) in [(10_000_000.0, 5_000_000.0), (950_000, 50_000), (90_000, 10_000), (9000, 1000)] {
            XCTAssertLessThanOrEqual(EDXRoomFormat.axisCounts(v, step: step, locale: us).count, 6, "\(v)")
        }
    }

    func testTheStrobePeakIsBelowTheFirstLineAnyoneQuantifies() {
        XCTAssertLessThan(EDXSpectrumWindow.strobeCeilingKeV, EDXRoomFormat.fitToMinimumKeV)
        XCTAssertGreaterThan(EDXSpectrumWindow.strobeCeilingKeV, 0)
    }
}
