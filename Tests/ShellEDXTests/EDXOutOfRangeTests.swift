//
//  EDXOutOfRangeTests.swift
//  An atomic number outside the table or a count past Int is written, never an index out of range or `Int` overflow (MacEMUI#124).
//

import XCTest
@testable import ShellEDXModel
@testable import ShellSpectroscopy

nonisolated final class EDXOutOfRangeTests: XCTestCase {
    func testAnAtomicNumberOutsideTheTableIsNamedByNumber() {
        XCTAssertEqual(EDXElements.symbol(z: 0), "Z=0")
        XCTAssertEqual(EDXElements.symbol(z: 119), "Z=119")
        XCTAssertEqual(EDXElements.symbol(z: 26), "Fe")
        XCTAssertEqual(EDXElements.symbol(z: 118), "Og")
    }

    func testACountPastIntIsADash() {
        XCTAssertEqual(EDXRoomFormat.counts(1e300), "–")
        XCTAssertEqual(EDXRoomFormat.counts(.nan), "–")
        XCTAssertEqual(EDXRoomFormat.counts(1_234_567), "1\u{2009}234\u{2009}567")
    }
}
