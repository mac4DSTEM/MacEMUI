//
//  EDXSheetNumberTests.swift
//  2026-11-05, on a German-locale Mac: the typed-k sheet read "1.9476" as 19 476 300 000 000 (SwiftUI's `.number` parse takes the
//  period for grouping) and quantified with it, with no warning. The EDS sheets' fields now parse through `DecimalEntryFormat`.
//

import Foundation
import XCTest
import ShellControls
@testable import ShellSpectroscopy

nonisolated final class EDXSheetNumberTests: XCTestCase {
    private let german = Locale(identifier: "de_DE")
    private let american = Locale(identifier: "en_US")

    private func parse(_ text: String, _ locale: Locale, digits: ClosedRange<Int> = 1...6) throws -> Double {
        try EDXSheetNumber.format(digits: digits, locale: locale).parseStrategy.parse(text)
    }

    /// The reproduction: the format the sheets used before, under de_DE, does not read "1.9476" as 1.9476.
    func testTheOldFormatMisreadsAPeriodUnderGerman() throws {
        let old = FloatingPointFormatStyle<Double>.number.precision(.significantDigits(1...6)).locale(german)
        XCTAssertNotEqual((try? old.parseStrategy.parse("1.9476")) ?? .nan, 1.9476, accuracy: 1e-9)
    }

    /// Either separator is the decimal point under de_DE and en_US: the typed k-factors of the Al-Mg-Si demo.
    func testBothSeparatorsReadAsTheDecimalPoint() throws {
        for locale in [german, american] {
            XCTAssertEqual(try parse("1.9476", locale), 1.9476, accuracy: 1e-12, "\(locale.identifier)")
            XCTAssertEqual(try parse("1,9476", locale), 1.9476, accuracy: 1e-12, "\(locale.identifier)")
            XCTAssertEqual(try parse("1.16691", locale), 1.16691, accuracy: 1e-12, "\(locale.identifier)")
            XCTAssertEqual(try parse("1", locale), 1, "\(locale.identifier)")
            XCTAssertEqual(try parse("20", locale, digits: 1...4), 20, "\(locale.identifier)")
        }
    }

    /// Text with no single reading is refused, never turned into another number.
    func testAmbiguousTextIsRefused() {
        XCTAssertThrowsError(try parse("1.9.476", german))
        XCTAssertThrowsError(try parse("1,94,76", german))
        XCTAssertThrowsError(try parse("19.4.", german))
    }

    /// The shown value carries no grouping, so a value committed unchanged reads back as itself.
    func testTheShownValueReadsBackAsItself() throws {
        let f = EDXSheetNumber.format(digits: 1...6, locale: german)
        for v in [1.9476, 1234.5, 0.00275] {
            XCTAssertEqual(try f.parseStrategy.parse(f.format(v)), v, accuracy: 1e-9 * max(1, v))
        }
    }
}
