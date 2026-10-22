// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEMTests/DecimalEntryFormatTests.swift (no macTEM counterpart)
// Changes: `@testable import ShellControls`; classes nonisolated, the `NumberEntryField.resolve` tests need no actor (it is nonisolated); assertions identical.
// END MOVED FROM
//
//  DecimalEntryFormatTests.swift
//  Gate D, 2026-09-30 (Session queue S3): in a region whose decimal separator
//  is a comma, the system's lenient number parse read a typed period as
//  grouping — `0.0275` → 275, `0.020` → 20, `0.2` → 0 (which cleared the
//  file's Q). Reproduced in the app (en_US with the German region) and with
//  `FloatingPointParseStrategy` directly. These pin `DecimalEntryFormat`,
//  which every numeric field now parses and displays through.
//

import Foundation
import XCTest
@testable import ShellControls

nonisolated final class DecimalEntryFormatTests: XCTestCase {
    private let german = Locale(identifier: "en_US@rg=dezzzz")
    private let american = Locale(identifier: "en_US")

    private func decimal(_ locale: Locale) -> DecimalEntryFormat<FloatingPointFormatStyle<Double>> {
        DecimalEntryFormat(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...6)).locale(locale),
                           locale: locale)
    }

    private func parse(_ text: String, _ locale: Locale) throws -> Double {
        try decimal(locale).parseStrategy.parse(text)
    }

    /// The owner's own numbers, typed with a period in the German region —
    /// each was silently off by 10³–10⁴ (or zero) before.
    func testAPeriodIsTheDecimalPointInACommaRegion() throws {
        XCTAssertEqual(try parse("0.0275", german), 0.0275, accuracy: 1e-12)
        XCTAssertEqual(try parse("0.020", german), 0.02, accuracy: 1e-12)
        XCTAssertEqual(try parse("0.2", german), 0.2, accuracy: 1e-12)
        XCTAssertEqual(try parse("19.50", german), 19.5, accuracy: 1e-12)
        XCTAssertEqual(try parse("200.5", german), 200.5, accuracy: 1e-12)
        XCTAssertEqual(try parse("0,0275", german), 0.0275, accuracy: 1e-12)
    }

    func testACommaIsTheDecimalPointInAPeriodRegion() throws {
        XCTAssertEqual(try parse("0,2", american), 0.2, accuracy: 1e-12)
        XCTAssertEqual(try parse("0,020", american), 0.02, accuracy: 1e-12)
        XCTAssertEqual(try parse("0.0275", american), 0.0275, accuracy: 1e-12)
    }

    func testBothSeparatorsMeanTheLastIsTheDecimalPoint() throws {
        for locale in [german, american] {
            XCTAssertEqual(try parse("1.234,5", locale), 1234.5, accuracy: 1e-9)
            XCTAssertEqual(try parse("1,234.5", locale), 1234.5, accuracy: 1e-9)
            XCTAssertEqual(try parse("1.000.000", locale), 1_000_000, accuracy: 1e-6)
        }
    }

    /// What a field shows, committed unchanged, is the value it showed —
    /// which needs the display ungrouped: `1.600` would read back as 1.6.
    func testTheDisplayRoundTripsWithoutGrouping() throws {
        for locale in [german, american] {
            let format = decimal(locale)
            XCTAssertEqual(format.format(1600), "1600")
            for value in [1600, 0.045741, 0.02, 200, 1234.5, 0.000001, -0.5] {
                XCTAssertEqual(try format.parseStrategy.parse(format.format(value)), value,
                               accuracy: 1e-9, "\(locale.identifier): \(format.format(value))")
            }
        }
    }

    /// Refuter (2026-09-30): repeated separators read as grouping without a
    /// group-size check turned typos back into the 10³–10⁴ error — `0.0.275`
    /// → 275, `300.5.` → 3005. A typo is refused, so the field keeps its value.
    func testTyposAreRefusedNotRead() {
        for locale in [german, american] {
            for typo in ["0.0.275", "300.5.", "1,5,", "0..2", "1.23,4", "0,02,5"] {
                XCTAssertThrowsError(try parse(typo, locale), "\(locale.identifier): \(typo)")
            }
        }
    }

    /// An integer field takes a separator only as grouping, never truncates:
    /// `1.600` iterations is 1600, not 1; `1.9` is refused, not 1.
    func testIntegerFieldsTakeSeparatorsOnlyAsGrouping() throws {
        for locale in [german, american] {
            let format = DecimalEntryFormat(IntegerFormatStyle<Int>.number.locale(locale), locale: locale)
            XCTAssertEqual(format.format(1600), "1600")
            XCTAssertEqual(try format.parseStrategy.parse("1600"), 1600)
            XCTAssertEqual(try format.parseStrategy.parse("1.600"), 1600)
            XCTAssertEqual(try format.parseStrategy.parse("1,600"), 1600)
            XCTAssertThrowsError(try format.parseStrategy.parse("1.9"))
        }
    }

    /// An empty entry is not a number: it throws, so the field keeps the value
    /// in effect instead of committing zero.
    func testAnEmptyEntryIsNotZero() {
        XCTAssertThrowsError(try parse("", german))
        XCTAssertThrowsError(try parse("  ", american))
    }
}

/// Drive 2026-09-30: the field committed every parseable prefix while typing.
/// `NumberEntryField` commits on Return / focus loss by this rule only.
nonisolated final class NumberEntryCommitRuleTests: XCTestCase {
    private typealias Field = NumberEntryField<Double, FloatingPointFormatStyle<Double>>
    private let entry = DecimalEntryFormat(
        FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...6)).locale(Locale(identifier: "en_US@rg=dezzzz")),
        locale: Locale(identifier: "en_US@rg=dezzzz"))

    func testATypoKeepsTheValueInsteadOfItsLastGoodPrefix() {
        XCTAssertEqual(Field.resolve(typed: "0.0.275", current: 0.1904, emptyClears: false, entry: entry), .keep)
        XCTAssertEqual(Field.resolve(typed: "300.5.", current: 200, emptyClears: false, entry: entry), .keep)
    }

    func testAnEmptyFieldKeepsOrClearsAsTheFieldSays() {
        XCTAssertEqual(Field.resolve(typed: "  ", current: 0.1904, emptyClears: false, entry: entry), .keep)
        XCTAssertEqual(Field.resolve(typed: "", current: 0.3, emptyClears: true, entry: entry), .set(nil))
        XCTAssertEqual(Field.resolve(typed: "", current: nil, emptyClears: true, entry: entry), .keep)
    }

    func testTheSameValueDoesNotCommitAndANewOneDoes() {
        XCTAssertEqual(Field.resolve(typed: "0,1904", current: 0.1904, emptyClears: false, entry: entry), .keep)
        XCTAssertEqual(Field.resolve(typed: "0.0275", current: 0.1904, emptyClears: false, entry: entry), .set(0.0275))
    }
}
