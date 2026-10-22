// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/UI/InspectorRows.swift lines 1076-1099, 1106-1109 and 1198-1205 (macTEM@51c944c macTEM/UI/InspectorRows.swift: no macTEM differences folded in beyond the locale-free "%g", which mac4DSTEM's newer locale-aware form replaces)
// Changes: made public; only the members the shared rows and both apps use stay (briefHint, pixels, sectionHeaderValue); the room-specific strings and helpers stay in mac4DSTEM as an extension of RoomAccessibilityText
// END MOVED FROM
import Foundation
import SwiftUI

/// What VoiceOver says for values the screen shows as symbols, abbreviations or a prompt — pure strings, so a test can hold them
/// (../_archive/mac4DSTEM/docs/archive/v5/a11y-rooms-apple-docs-audit-2026-10-07.md, group Y2). Nothing here is drawn.
/// An app adds its own room strings in an extension of this enum.
public nonisolated enum RoomAccessibilityText {
    /// The longest hint left as it is: Apple asks for "a brief phrase" ("Purchases the item").
    public static let briefHintLimit = 100

    /// A one-phrase VoiceOver hint taken from a tooltip: its first sentence (up to ". ", ": " or "; "), without the closing
    /// period; none when there is no tooltip or that sentence is longer than `briefHintLimit` (the tooltip keeps the full text).
    public static func briefHint(from help: String?) -> String {
        guard let help else { return "" }
        var sentence = help.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [". ", ": ", "; "] {
            if let range = sentence.range(of: separator) { sentence = String(sentence[..<range.lowerBound]) }
        }
        while sentence.hasSuffix(".") { sentence.removeLast() }
        return sentence.count <= briefHintLimit ? sentence : ""
    }

    /// A pixel count spoken in full ("px" is read letter by letter): "1 pixel", "12 pixels".
    public static func pixels(_ value: Double) -> String {
        let text = value == value.rounded() ? String(Int(value)) : String(format: "%g", locale: .autoupdatingCurrent, value)
        return value == 1 ? "1 pixel" : "\(text) pixels"
    }

    /// A section header's value: the stage status when it has one, then whether it is open.
    public static func sectionHeaderValue(status: String?, expanded: Bool) -> String {
        [status, expanded ? "Expanded" : "Collapsed"].compactMap { $0 }.joined(separator: ", ")
    }
}

extension View {
    /// Selectable text whose words can change. `.textSelection(.enabled)` wraps a Text in an outer accessibility
    /// element whose value is captured once and never updates (drives 9, 13, 14: VoiceOver read "144 positions" while
    /// the screen read 81; measured on a scratch app 2026-10-13); an explicit value keeps it current.
    public func selectableText(_ shown: String) -> some View {
        textSelection(.enabled).accessibilityValue(shown)
    }
}
