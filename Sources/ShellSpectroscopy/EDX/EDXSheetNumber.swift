//
//  EDXSheetNumber.swift
//  Role: the number format of the EDS sheets' typed fields (k-factors, zeta / cross-section factors, dose). SwiftUI's own `.number`
//        parse, in a region whose decimal separator is a comma, reads a typed period as grouping: "1.9476" became 19 476 300 000 000
//        in the typed-k sheet on a German Mac, with no warning (MacEMUI issue, 2026-11-05). These fields now parse through
//        `DecimalEntryFormat`, the rule every inspector number already uses: one `.` or `,` is the decimal point, well-formed
//        grouping is grouping, anything else is refused (the field keeps its last value).
//

import Foundation
import ShellControls

nonisolated enum EDXSheetNumber {
    /// A decimal field with `digits` significant digits, either separator accepted.
    static func format(digits: ClosedRange<Int>, locale: Locale = .autoupdatingCurrent) -> DecimalEntryFormat<FloatingPointFormatStyle<Double>> {
        DecimalEntryFormat(FloatingPointFormatStyle<Double>.number.precision(.significantDigits(digits)).locale(locale), locale: locale)
    }
}
