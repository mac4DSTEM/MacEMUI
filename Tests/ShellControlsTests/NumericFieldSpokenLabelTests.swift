// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEMTests/NumericFieldSpokenLabelTests.swift (no macTEM counterpart)
// Changes: `@testable import ShellControls`; class nonisolated; assertions identical.
// END MOVED FROM
import XCTest
@testable import ShellControls

/// SwiftUI-review residual A2 (drive 7, VoiceOver): a number field's drawn unit
/// is hidden from accessibility and folded into the field's spoken label, unless
/// the title already names it.
nonisolated final class NumericFieldSpokenLabelTests: XCTestCase {

    func testUnitIsFoldedIntoTheSpokenLabelWhenTheTitleDoesNotNameIt() {
        XCTAssertEqual(NumericFieldSpeech.label("KDE σ", unit: "px"), "KDE σ, px")
        XCTAssertEqual(NumericFieldSpeech.label("Minimum size", unit: "px"), "Minimum size, px")
        XCTAssertEqual(NumericFieldSpeech.label("σ_k", unit: "%"), "σ_k, %")
    }

    func testTitleThatAlreadyNamesTheUnitIsNotRepeated() {
        XCTAssertEqual(NumericFieldSpeech.label("Semi-axis a in pixels", unit: "px"), "Semi-axis a in pixels")
        XCTAssertEqual(NumericFieldSpeech.label("Energy (keV)", unit: "keV"), "Energy (keV)")
        XCTAssertEqual(NumericFieldSpeech.label("Thickness (nm)", unit: "nm"), "Thickness (nm)")
    }

    func testDegreeSignIsNamedByTheWordDegree() {
        // "°" is spoken as "degree": a title that says degrees does not repeat the sign.
        XCTAssertEqual(NumericFieldSpeech.label("Ellipse angle θ in degrees", unit: "°"),
                       "Ellipse angle θ in degrees")
        XCTAssertEqual(NumericFieldSpeech.label("Tilt", unit: "°"), "Tilt, °")
    }

    func testNoUnitLeavesTheTitleAlone() {
        XCTAssertEqual(NumericFieldSpeech.label("Inner fit radius in pixels", unit: nil),
                       "Inner fit radius in pixels")
    }

    func testAUnitInsideAnotherWordIsNotCountedAsNamed() {
        // "nm" is inside "Enmesh" but is not a separate word.
        XCTAssertEqual(NumericFieldSpeech.label("Enmesh", unit: "nm"), "Enmesh, nm")
    }
}
