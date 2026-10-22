// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/UI/LayoutPolicy.swift lines 336-413 (macTEM@51c944c macTEM/UI/NumericField.swift folded in: nothing; the block is identical)
// Changes: made public with a public init; `LayoutPolicy.numericFieldWidth` (ShellLayout, which depends on this module) became `NumericFieldMetrics.width` here, and LayoutPolicy should forward to it.
// END MOVED FROM

import SwiftUI

/// The width every numeric field takes, in points: the one place a form control gets a width. `LayoutPolicy.numericFieldWidth`
/// (ShellLayout) is this value, so the inspector's fields and the histogram's typed edges agree.
public nonisolated enum NumericFieldMetrics {
    public static let width: CGFloat = 72
}

/// A numeric text field with an optional unit, for the trailing side of a
/// `LabeledContent` row — the one place a UI form control takes a width.
public struct NumericField<Value: Equatable, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let title: String
    @Binding var value: Value
    let format: Format
    var unit: String?

    public init(
        _ title: String,
        value: Binding<Value>,
        format: Format,
        unit: String? = nil
    ) {
        self.title = title
        self._value = value
        self.format = format
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Commits on Return or focus loss, either decimal separator
            // (`NumberEntryField`, `DecimalEntryFormat`).
            NumberEntryField(title: title, value: value, format: format) {
                if let typed = $0 { value = typed }
            }
                // Labelled by the row it sits in; the title stays for
                // VoiceOver.
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: NumericFieldMetrics.width)
                // The unit is spoken with the field, not as a separate
                // element after it (the titles do not all carry it: "KDE σ"
                // has none, "Semi-axis a in pixels" does not name "px").
                .accessibilityLabel(NumericFieldSpeech.label(title, unit: unit))
            if let unit {
                // The unit is part of the number's meaning: it never
                // truncates and never wraps.
                Text(unit)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
    }
}

/// What VoiceOver says for a number field with a drawn unit. The unit is hidden
/// from accessibility and folded into the field's spoken label, unless the title
/// already names it: "Energy (keV)" + "keV" and "Semi-axis a in pixels" + "px"
/// are spoken once.
public nonisolated enum NumericFieldSpeech {
    public static func label(_ title: String, unit: String?) -> String {
        guard let unit, !unit.isEmpty else { return title }
        return namesUnit(title, unit) ? title : "\(title), \(unit)"
    }

    /// A unit that a title may spell out in words instead: "px" as "pixel",
    /// "°" as "degree". Keys are lowercased units.
    static let unitWords: [String: String] = [
        "px": "pixel",
        "°": "degree",
    ]

    /// Whether the title already says the unit: as a separate word or inside
    /// parentheses (case-insensitive), or as its spelled-out word in the title
    /// (see `unitWords`).
    static func namesUnit(_ title: String, _ unit: String) -> Bool {
        if let word = unitWords[unit.lowercased()], title.localizedCaseInsensitiveContains(word) {
            return true
        }
        let spaced = " " + title.lowercased().map { "(),;:".contains($0) ? " " : String($0) }.joined() + " "
        return spaced.contains(" " + unit.lowercased() + " ")
    }
}
