//
//  EDXResultsColumnsTests.swift
//  The results tables' number columns hold the longest "value ± σ" the formatter writes inside a stated bound, measured in the
//  font the table draws them in, so the σ is never cut off at the columns' minimum width.
//

import AppKit
import XCTest
@testable import ShellSpectroscopy

nonisolated final class EDXResultsColumnsTests: XCTestCase {
    /// `.body.monospacedDigit()`: what a Table cell draws its text in.
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private let locale = Locale(identifier: "en_US")

    private func widest(_ pairs: [(Double, Double)]) -> (text: String, width: CGFloat) {
        var out = (text: "", width: CGFloat(0))
        for (value, sigma) in pairs {
            let text = EDXRoomFormat.plusMinus(value, sigma, locale: locale)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            if width > out.width { out = (text, width) }
        }
        return out
    }

    /// at% and wt%: a value from 0 to 100 with a 1σ of 0.01 or more (three decimals at most; a finer σ is below what counting gives a pooled EDS fit).
    func testThePercentColumnsHoldTheLongestValueAndSigma() {
        let values: [Double] = [0, 0.05, 1, 9.999, 12.34, 50, 97.6, 99.999, 100]
        let sigmas: [Double] = [0.01, 0.0101, 0.0199, 0.05, 0.099, 0.5, 0.99, 1, 5, 9.9, 10, 50, 99]
        let w = widest(values.flatMap { v in sigmas.map { (v, $0) } })
        XCTAssertLessThanOrEqual(w.width + EDXResultsColumns.cellAllowance, EDXResultsColumns.percentMinimum,
                                 "\"\(w.text)\" is \(w.width) pt; widen EDXResultsColumns.percentMinimum, do not let the σ be cut off")
    }

    /// Net counts: up to 10^8 counts in a line window, with a counting 1σ (at least the square root of the counts, at least 0.1).
    func testTheNetColumnsHoldTheLongestValueAndSigma() {
        var pairs: [(Double, Double)] = []
        for e in 0...8 {
            for m in [1.0, 4.99, 9.99] {
                let net = min(m * pow(10, Double(e)), 99_999_999)
                let floor = max(net.squareRoot(), 0.1)
                for k in [1.0, 1.9, 3, 9.9] { pairs.append((net, floor * k)) }
            }
        }
        pairs += [(0.4, 0.1), (-12.5, 3.6), (-999.0, 99)]
        let w = widest(pairs)
        XCTAssertLessThanOrEqual(w.width + EDXResultsColumns.cellAllowance, EDXResultsColumns.netMinimum,
                                 "\"\(w.text)\" is \(w.width) pt; widen EDXResultsColumns.netMinimum, do not let the σ be cut off")
    }

    /// Both tables take the measured widths (a column that went back to a literal would cut the σ again).
    func testTheTablesTakeTheMeasuredWidths() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let panel = try String(contentsOf: root.appendingPathComponent("Sources/ShellSpectroscopy/EDX/EDXResultsPanel.swift"), encoding: .utf8)
        XCTAssertEqual(panel.components(separatedBy: "min: EDXResultsColumns.netMinimum").count - 1, 2, "the window table and the fit table")
        XCTAssertEqual(panel.components(separatedBy: "min: EDXResultsColumns.percentMinimum").count - 1, 2, "at% and wt%")
    }
}
