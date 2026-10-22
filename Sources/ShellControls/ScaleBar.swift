// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/UI/PaneOverlays.swift lines 76-198 (macTEM@51c944c macTEM/UI/PaneOverlays.swift folded in: the bar's numbers (`nice125`, `ladder`, the digits of `format`) are ImagoKit's `ScaleBarMath`, as macTEM already has them; the localised `format`, the spoken label and the layout stay here)
// Changes: made public; `ladder` and `nice125` removed (callers use `ScaleBarMath`); `footerSampling` NOT moved (it names the app's unit-label table); `format` no longer calls the app's `CalibrationUnitConversion.localizedDecimal` (same rule inlined).
// END MOVED FROM

import ImagoCore
import SwiftUI

// MARK: - Scale bar

/// Calibrated scale bar overlay for the image panes. Picks a "nice" 1-2-5
/// length near a target on-screen size, so it re-quantizes as the user zooms.
/// Falls back to pixel units when no calibration exists — an uncalibrated bar
/// labelled "px" is still honest and useful.
public struct ScaleBar: View {
    /// Physical units per screen POINT at the current zoom
    /// (= pixelSize * imagePixels / (fittedWidthPoints * zoom)).
    let unitsPerPoint: Double
    /// Unit label ("nm", "1/nm", "px", …).
    let unitLabel: String

    /// The length the bar aims at, in points; public so an app that speaks the bar in its own words (macTEM's transform) holds its number to this one.
    public static let targetPoints = 70.0

    public init(unitsPerPoint: Double, unitLabel: String) {
        self.unitsPerPoint = unitsPerPoint
        self.unitLabel = unitLabel
    }

    public var body: some View {
        if unitsPerPoint > 0, unitsPerPoint.isFinite {
            let nice = ScaleBarMath.nice125(unitsPerPoint * Self.targetPoints)
            let lengthPt = CGFloat(nice / unitsPerPoint)
            let shown = ScaleBarMath.ladder(nice, unit: unitLabel)
            VStack(alignment: .leading, spacing: 3) {
                // verbatim: the label is data, not a localisation key.
                Text(verbatim: "\(Self.format(shown.value)) \(shown.unit)")
                    .accessibilityLabel(Self.spokenLabel(value: shown.value, unit: shown.unit))
                Rectangle()
                    .frame(width: lengthPt, height: 2)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            // Legibility plate: this sits on top of arbitrary scientific
            // image data, where white-on-white is unreadable. Not chrome.
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
            .allowsHitTesting(false)
        }
    }

    /// The unit as VoiceOver should say it ("nm" is read letter by letter
    /// otherwise). Covers every spelling the app's unit-label table
    /// can hand the bar; an unknown unit is spoken as written.
    public nonisolated static func spokenUnit(_ unit: String) -> String {
        switch unit {
        case "nm": return "nanometres"
        case "\u{00B5}m", "\u{03BC}m", "um": return "micrometres"
        case "mm": return "millimetres"
        case "pm": return "picometres"
        case "\u{00C5}", "A": return "\u{00E5}ngstr\u{00F6}ms"
        case "1/nm", "nm\u{207B}\u{00B9}", "nm^-1": return "inverse nanometres"
        case "1/\u{00C5}", "\u{00C5}\u{207B}\u{00B9}", "A^-1": return "inverse \u{00E5}ngstr\u{00F6}ms"
        case "mrad": return "milliradians"
        case "px": return "pixels"
        default: return unit
        }
    }

    /// "Scale bar, 10 nanometres" - the number as the bar prints it.
    public nonisolated static func spokenLabel(value: Double, unit: String, locale: Locale = .autoupdatingCurrent) -> String {
        // "1 nanometre", not "1 nanometres": the bar's 1-2-5 values reach exactly 1.
        let spoken = spokenUnit(unit)
        let unitWords = value == 1 && spoken != unit && spoken.hasSuffix("s") ? String(spoken.dropLast()) : spoken
        return "Scale bar, \(format(value, locale: locale)) \(unitWords)"
    }

    /// The bar's number in the reader's locale ("0,05" in de_DE). The digits are
    /// the C-format ones the bar always printed (`ScaleBarMath.format`); only the decimal separator is
    /// localised, so en output is byte-identical. Exports burn with en_US_POSIX.
    public nonisolated static func format(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let text = ScaleBarMath.format(value)
        guard let mark = locale.decimalSeparator, mark != "." else { return text }
        return text.replacingOccurrences(of: ".", with: mark)
    }
}
