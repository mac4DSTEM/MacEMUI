// Pins `ProvenanceValueText.display` (the app's tests only reach it through InspectorRows). Behaviour is the documented rule, not a new one.
import XCTest
@testable import ShellControls

nonisolated final class ProvenanceValueTextTests: XCTestCase {
    func testALongDecimalPrintsAtFiveSignificantFigures() {
        // The rule prints in the reader's locale; compare on the digits.
        XCTAssertEqual(ProvenanceValueText.display("10.056641535141353").replacingOccurrences(of: ",", with: "."), "10.057")
    }

    func testShortNonNumericAndOutOfRangeValuesAreLeftAsWritten() {
        XCTAssertEqual(ProvenanceValueText.display("0.0275"), "0.0275")
        XCTAssertEqual(ProvenanceValueText.display("Velox EMD"), "Velox EMD")
        XCTAssertEqual(ProvenanceValueText.display("1.2345678901e-05"), "1.2345678901e-05")
        XCTAssertEqual(ProvenanceValueText.display("123456789.123456"), "123456789.123456")
    }
}
