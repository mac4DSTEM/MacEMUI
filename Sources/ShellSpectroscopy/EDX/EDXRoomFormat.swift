//
//  EDXRoomFormat.swift
//  Role: the EDX room's strings and small pure rules, held apart from the views so a test can pin them: counts with a
//        thin-space grouping, the at% cell, the region sentence, the spectrum's automatic window and the colour of an
//        element's map. No SwiftUI.
//

import Foundation
import SpectroCore
import SpectroEDX
import ShellEDXModel

/// The EDX room's own sizes, named once (the chrome's numbers are `LayoutPolicy`'s, a frozen shell file; these belong to the
/// room's content and are the room's explained constants: UI contract rule 4).
public nonisolated enum EDXLayout {
    /// A periodic-table cell is 18 pt tall (the 320-pt inspector holds 18 of them at about 17 pt wide); the gap before the folded rows is 4.
    /// The sheets that type factors: the number fields (k, σ, a factor), the sheet widths.
    public static let kFieldWidth: CGFloat = 90
    public static let sigmaFieldWidth: CGFloat = 70
    public static let factorFieldWidth: CGFloat = 110
    public static let typedKSheetWidth: CGFloat = 380
    public static let factorsSheetWidth: CGFloat = 400
    /// The scale bar's thickness in a figure.
    public static let figureBarThickness: CGFloat = 3
    /// The EELS header's progress bar; the particle table sheet's smallest size.
    public static let progressBarWidth: CGFloat = 90
    public static let tableSheetMinimum = CGSize(width: 560, height: 360)
    /// The opening bar.
    public static let openingBarWidth: CGFloat = 260
    /// The lower pane (spectrum and results) is never less than 230 pt, so the maps keep the rest.
    public static let lowerPaneMinimumHeight: CGFloat = 230
    /// The spectrum needs 280 pt to read; the results table 300, ideally 420, at most 520.
    public static let spectrumMinimumWidth: CGFloat = 280
    public static let resultsWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (300, 420, 520)
}

public nonisolated enum EDXRoomFormat {
    public static let openPrompt = "Open a Velox .emd or a GMS .dm4 spectrum image."
    public static let emptyTitle = "No spectrum image open"
    public static let noElementsDetail = "Pick elements in the periodic table, or let Auto ID propose them."

    /// The header's status text, secondary and never a control (design §2.3): "Quantified · live ✓" once the fit follows every change,
    /// "Identified" once an element is picked to quantify, nothing before.
    public static func statusText(quantified: Bool, hasPicks: Bool) -> String? {
        if quantified { return "Quantified · live ✓" }
        return hasPicks ? "Identified" : nil
    }

    /// 1 234 567: a thin space between thousands, whatever the locale.
    public static func counts(_ v: Double) -> String {
        guard v.isFinite else { return "–" }
        let digits = String(Int(v.rounded().magnitude))
        var out = ""
        for (i, c) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append("\u{2009}") }
            out.append(c)
        }
        return (v < 0 ? "−" : "") + String(out.reversed())
    }

    /// "12.35 ± 0.56": a value and its 1σ, the σ to two significant digits and the value to the same decimal place.
    public static func plusMinus(_ value: Double, _ sigma: Double, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "–" }
        guard sigma.isFinite, sigma > 0 else { return Num.fixed(value, 2, locale: locale) }
        let places = max(0, min(4, 1 - Int(floor(log10(sigma)))))
        return "\(Num.fixed(value, places, locale: locale)) \u{00B1} \(Num.fixed(sigma, places, locale: locale))"
    }

    /// "Whole map" or "Region · x 10–40, y 5–30 (900 px)".
    public static func region(_ r: EDXRegion, pixels: Int) -> String {
        switch r {
        case .wholeMap: "Whole map · \(counts(Double(pixels))) px"
        case .rectangle(let p): "Region · x \(p.x0)–\(p.x1 - 1), y \(p.y0)–\(p.y1 - 1) · \(counts(Double(pixels))) px"
        case .ellipse(let p): "Ellipse · x \(p.x0)–\(p.x1 - 1), y \(p.y0)–\(p.y1 - 1) · \(counts(Double(pixels))) px"
        case .polygon(let v): "Polygon · \(v.count) vertices · \(counts(Double(pixels))) px"
        case .pool(let p): "\(p.name) · \(p.kind == "group" ? "group" : p.kind == "notIndexed" ? "not indexed" : "phase") pool · \(counts(Double(pixels))) px"
        }
    }

    /// The infobar-sized line under the room's title: the counts in the region.
    public static func spectrumSubtitle(counts total: UInt64, region r: EDXRegion, pixels: Int) -> String {
        "\(counts(Double(total))) counts · " + region(r, pixels: pixels)
    }

    /// The toolbar's display after the file and the room: the grid, what the spectrum sums and what the fit is doing, e.g. "215 × 926 px · 16 090 312 counts · Region 1 · 5 092 px · Quantified".
    @MainActor public static func capsuleDetail(_ session: EDXSession) -> String {
        guard let meta = session.source?.metadata else { return "spectrum image" }
        var parts = [session.isSingleSpectrum ? "single spectrum" : "\(meta.scanWidth) × \(meta.scanHeight) px"]
        parts.append(counts(Double(session.totalCounts)) + " counts")
        if !session.isSingleSpectrum {
            let name = session.selectedPin?.name ?? "Whole map"
            parts.append("\(name) · \(session.regionPixels) px")
        }
        if let status = statusText(quantified: session.quantifyActive, hasPicks: session.canQuantify) { parts.append(status) }
        return parts.joined(separator: " · ")
    }

    /// "Al Kα, Si Kα" for a hover; the picked elements' lines the spectrum marks.
    public static func lines(_ markers: [EDXMarker]) -> String { markers.map(\.label).joined(separator: ", ") }

    // MARK: Spectrum window

    /// The window a spectrum opens in: from 0 to a little past the highest marked line, or, with none, to where 99.5 % of the
    /// counts lie; never narrower than 2 keV nor wider than the axis (mac4DSTEM's `SpectrumAutoZoom`, simplified).
    public static func autoWindow(plot: EDXPlot, markers: [EDXMarker]) -> ClosedRange<Double> {
        guard plot.energyStep > 0, !plot.data.isEmpty else { return 0...20 }
        let end = plot.energyStart + plot.energyStep * Double(plot.data.count)
        var hi = markers.map(\.energy).max().map { $0 * 1.25 + 0.5 } ?? 0
        if hi == 0 {
            let total = plot.data.reduce(0, +)
            var run = 0.0
            for (i, c) in plot.data.enumerated() {
                run += c
                if run >= 0.995 * total { hi = plot.energyStart + plot.energyStep * Double(i + 1); break }
            }
        }
        hi = min(max(hi, 2), 20, end)
        return max(plot.energyStart, 0)...max(hi, plot.energyStart + 2 * plot.energyStep)
    }

    // MARK: Map colours

    /// A map's hue by atomic number: the golden-angle walk keeps neighbouring elements apart.
    public static func hue(symbol: String) -> Double {
        let z = Double(EDXElements.z(of: symbol) ?? 0)
        return (z * 0.381966).truncatingRemainder(dividingBy: 1)
    }

    /// The colour of a map's hue as the maps draw it at full brightness (saturation 0.85), as sRGB numbers.
    public static func rgb(hue: Double) -> (Double, Double, Double) {
        let h = (hue - floor(hue)) * 6, f = h - Double(Int(h)), v = 1.0, sat = 0.85
        let p = v * (1 - sat), q = v * (1 - sat * f), t = v * (1 - sat * (1 - f))
        switch Int(h) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    // MARK: Fit rows

    public struct FitRow: Identifiable, Equatable {
        public let element: String
        public let line: String
        public let net: String
        /// The reference element of the computed k (its k is 1 by definition).
        public var isReference = false
        public let atPercent: String
        public let wtPercent: String
        /// The wt% as a number, for the accessibility value a UI test reads.
        public let wtValue: Double?
        public let note: String?
        public var id: String { element + "|" + line }
    }

    /// The table of a fit: the quantified elements, fitted area and composition, a failure or a flag in the note.
    public static func fitRows(_ q: PooledQuantification) -> [FitRow] {
        q.rows.map { r in
            var note: [String] = []
            if let f = r.failure { note.append(f) }
            if let n = r.lineNote, r.failure == nil { note.append(n) }
            if r.atBound && r.failure == nil { note.append("held at 0 by the non-negativity bound: not detected, read σ as an upper-limit scale") }
            return FitRow(element: r.element, line: ElementWindows.label(ofLineID: r.groupID), net: plusMinus(r.net, r.sigma), isReference: r.isReference,
                          atPercent: r.atomicPercent.map { plusMinus($0, r.atomicSigma ?? 0) } ?? "–",
                          wtPercent: r.weightPercent.map { plusMinus($0, r.weightSigma ?? 0) } ?? "–", wtValue: r.weightPercent,
                          note: note.isEmpty ? nil : note.joined(separator: "; "))
        }
    }

    /// The lowest upper end of the fitted range the Fit to field takes, keV: below it no line of the table is left to fit.
    public static let fitToMinimumKeV = 0.2

    /// What a Fit to entry does: a value above the minimum is the range's upper end; zero is the default (nil, no note); any other value at or
    /// below the minimum, negative included, is refused, the default kept, and the note says so instead of the field resetting silently.
    public static func fitTo(entered v: Double, locale: Locale = .autoupdatingCurrent) -> (keV: Double?, refusal: String?) {
        guard v.isFinite else { return (nil, nil) }
        if v > fitToMinimumKeV { return (v, nil) }
        if v == 0 { return (nil, nil) }
        return (nil, "Fit to must be above \(Num.sig(fitToMinimumKeV, 2, locale: locale)) keV: the default range is used.")
    }

    /// "Fit quality · χ²ᵣ 1.04 · Pearson": the kit's own text.
    public static func fitQuality(_ q: PooledQuantification) -> String {
        let t = q.qualityText
        guard t.hasSuffix(")"), let open = t.range(of: " (", options: .backwards) else { return t }
        return String(t[..<open.lowerBound]) + " \u{00B7} " + t[open.upperBound..<t.index(before: t.endIndex)]
    }
}
