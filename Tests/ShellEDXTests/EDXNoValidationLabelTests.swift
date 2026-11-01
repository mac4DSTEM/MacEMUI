//
//  EDXNoValidationLabelTests.swift
//  The EDX room shows its results as scientific software does: the method a number comes from, never an "unvalidated" badge or a
//  "validation: none" caption, on screen or in an export the room writes.
//

import Foundation
import XCTest
import SpectroEDX
@testable import ShellEDXModel
@testable import ShellSpectroscopy

nonisolated final class EDXNoValidationLabelTests: XCTestCase {
    func testTheResultsHeaderNamesTheMethod() {
        var m = QuantificationMethod()
        XCTAssertEqual(EDXRoomFormat.methodCaption(m), "Cliff-Lorimer \u{00B7} computed k")
        m.kFactorSource = .typed
        XCTAssertEqual(EDXRoomFormat.methodCaption(m), "Cliff-Lorimer \u{00B7} typed k")
        m.kSource = "Lab standard 2026"
        XCTAssertEqual(EDXRoomFormat.methodCaption(m), "Cliff-Lorimer \u{00B7} k from Lab standard 2026")
    }

    func testTheComputedKSourceLosesOnlyItsValidationClause() {
        XCTAssertEqual(EDXQuantMaps.sourceWithoutValidationClause("Bote-Salvat 2008; relative to Al; beam 200.0 keV; UNVALIDATED"),
                       "Bote-Salvat 2008; relative to Al; beam 200.0 keV")
        XCTAssertEqual(EDXQuantMaps.sourceWithoutValidationClause("Lab standard; 2026"), "Lab standard; 2026")
    }

    func testThePinnedRegionsCSVCarriesNoValidationLabel() {
        let csv = EDXPins.csv(rows: [], fileName: "a.emd", title: "EDX regions")
        XCTAssertTrue(csv.contains("Cliff-Lorimer"), csv)
        XCTAssertFalse(csv.localizedCaseInsensitiveContains("validat"), csv)
    }

    /// The room's views say no "validation none" or "unvalidated" in any text a person reads (labels, help, notes); the model's
    /// footers and CSV are checked by their output above and in EDXMapsTests.
    func testTheRoomViewsCarryNoValidationLabel() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folders = ["Sources/ShellSpectroscopy/EDX"]
        var checked = 0
        for folder in folders {
            let dir = root.appendingPathComponent(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where name.hasSuffix(".swift") {
                let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
                for phrase in ["validation none", "validation: none", "unvalidated", "validationBadge", "validation: \\("] {
                    XCTAssertFalse(text.localizedCaseInsensitiveContains(phrase), "\(folder)/\(name) says \(phrase)")
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 10)
    }
}
