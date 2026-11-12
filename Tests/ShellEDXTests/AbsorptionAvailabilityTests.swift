//
//  AbsorptionAvailabilityTests.swift
//  The Absorption switch is off and disabled where the file gives no detector geometry. On a GMS file it stood on beside
//  the fit's "Absorption not applied", which said two things at once (seen driving a GMS 4D + EDS file, Nov 2026).
//

import XCTest
import SpectroCore
@testable import ShellEDXModel

nonisolated final class AbsorptionAvailabilityTests: XCTestCase {
    func testAGMSFileHasNoAbsorptionGeometryAndSaysWhy() throws {
        let reason = try XCTUnwrap(EDXSession.absorptionUnavailableReason(origin: .gmsDM4))
        XCTAssertTrue(reason.contains("stage tilt") && reason.contains("detector geometry"), reason)
        XCTAssertLessThan(reason.count, 140, "a help line, not a paragraph")
    }

    func testEveryOtherFileKeepsTheSwitch() {
        XCTAssertNil(EDXSession.absorptionUnavailableReason(origin: nil), "no file, or a file that does not say where it is from")
        XCTAssertNil(EDXSession.absorptionUnavailableReason(origin: .veloxEMD), "a Velox file states its detectors and tilts")
    }
}
