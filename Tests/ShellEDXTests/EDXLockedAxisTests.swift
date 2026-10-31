//
//  EDXLockedAxisTests.swift
//  A locked energy axis on a GMS file: what the room says about the axis. On EDXSessionTests' planted two-pixel Al-Mg-Si image,
//  stamped as a GMS file, with the method's axis lock on.
//
//  Checked 31 Oct 2026 against SpectroKit 0.12.0: the locked axis reads "energy axis: the file's (locked)" and no axis sentence
//  carries a zero shift. The only "+0.0 %" on such a fit is the kit's range-sensitivity line ("if fitted to 79.97 keV, Mg +0.0 %
//  (+0.0 σ), ..."), which any axis past 20 keV gets, locked or not; its wording is the kit's (`FitRangeSensitivity.line`).
//

import XCTest
import SpectroCore
import SpectroEDX
@testable import ShellEDXModel

nonisolated final class EDXLockedAxisTests: XCTestCase {

    /// Every sentence the room shows after Quantify: the fit's footer, warnings and caveat, the rows' sigma sentences, Auto ID's notes.
    @MainActor private func shownText(_ session: EDXSession) throws -> [String] {
        let fit = try XCTUnwrap(session.fit, session.fitFailure ?? "no fit")
        var out = fit.footerLines + fit.warnings
        if let caveat = fit.abundanceCaveat { out.append(caveat) }
        for row in fit.rows { out += [row.atomicTermsText, row.weightTermsText].compactMap { $0 } }
        if case .done(let outcome) = session.autoID { out += outcome.notes }
        return out
    }

    @MainActor private func quantified(origin: SpectrumImageOrigin, locked: Bool) async throws -> EDXSession {
        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source(origin: origin)).value
        await session.settled()
        if locked { session.changeMethod { $0.lockEnergyAxis = true } }
        await session.quantify()?.value
        await session.settled()
        return session
    }

    /// A locked axis on a GMS file says "the file's (locked)" and nothing else about the axis: no refined offset or gain, and no
    /// zero shift dressed as a measurement ("+0.0 eV", "+0.000 %", "0.0 %" beside the axis). Red under: the locked fit still
    /// printing the refinement line, or a zero gain statement for an axis that was never refined.
    @MainActor func testALockedGMSAxisMakesNoTrivialShiftStatement() async throws {
        let session = try await quantified(origin: .gmsDM4, locked: true)
        let fit = try XCTUnwrap(session.fit)
        XCTAssertTrue(fit.axisLocked)
        XCTAssertTrue(fit.refinement == nil, "a locked axis is not refined")
        XCTAssertEqual(fit.usedAxis, try XCTUnwrap(session.source).energyAxis, "the file's axis is the one used")
        let text = try shownText(session)
        let axisLines = text.filter { $0.localizedCaseInsensitiveContains("axis") || $0.localizedCaseInsensitiveContains("gain") }
        XCTAssertTrue(axisLines.contains("energy axis: the file's (locked)"), "\(axisLines)")
        for line in axisLines {
            for trivial in ["+0.0 eV", "+0.000 %", "-0.000 %", "\u{00B1}0.0 %", "\u{00B1} 0.0 %"] {
                XCTAssertFalse(line.contains(trivial), "a trivial axis statement: \(line)")
            }
        }
    }
}
