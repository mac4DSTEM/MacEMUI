import Foundation

/// A provenance value as a person reads it: a long decimal (`10.056641535141353`)
/// prints at 5 significant figures; anything short, non-numeric or outside
/// 0.001–99999 is left as written. Display only: the stored value and the
/// row's help text stay exact.
public nonisolated enum ProvenanceValueText {
    public static func display(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber).count
        guard digits > 7, !raw.contains("e"), !raw.contains("E"),
              let number = Double(raw), number.isFinite else { return raw }
        let magnitude = abs(number)
        guard magnitude >= 0.001, magnitude < 100_000 else { return raw }
        return String(format: "%.5g", locale: .autoupdatingCurrent, number)
    }
}
