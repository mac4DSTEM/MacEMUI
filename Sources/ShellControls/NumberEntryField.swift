import SwiftUI

/// How every numeric field reads and shows a number (2026-09-30). The system's lenient parse, in a region whose decimal
/// separator is a comma, read a typed period as grouping: `0.0275` became
/// 275 and `0.2` became 0 — silently, in the calibration fields. So:
/// - the value is shown without grouping (`1600`, never `1.600`), so a shown
///   number committed unchanged can never be re-read as another;
/// - in a decimal field one `.` or `,` typed is the decimal point, whichever
///   the region uses (declared trade-off: a US `1,600` is 1.6 here);
/// - anything else is grouping only in valid groups — 1–3 digits, then
///   exactly 3 (`1.234,5`, `1,234.5`, `1.000.000`); an integer field takes
///   separators only as grouping (`1.600` is 1600);
/// - every other placement is refused — the field keeps its value — so a
///   typo like `0.0.275` or `300.5.` can never become 275 or 3005.
public nonisolated struct DecimalEntryFormat<Inner: ParseableFormatStyle>: ParseableFormatStyle
where Inner.FormatOutput == String {
    var inner: Inner
    var locale: Locale

    public init(_ inner: Inner, locale: Locale = .autoupdatingCurrent) {
        self.inner = inner
        self.locale = locale
    }

    public func format(_ value: Inner.FormatInput) -> String {
        Self.ungrouped(inner.format(value), locale: locale)
    }

    public var parseStrategy: Strategy { Strategy(inner: inner, locale: locale) }

    public nonisolated struct Strategy: ParseStrategy {
        var inner: Inner
        var locale: Locale

        public func parse(_ value: String) throws -> Inner.FormatInput {
            let integer = Inner.FormatInput.self is any BinaryInteger.Type
            return try inner.parseStrategy.parse(
                DecimalEntryFormat.normalized(value, locale: locale, integer: integer))
        }
    }

    nonisolated struct Refused: Error {}

    static func ungrouped(_ text: String, locale: Locale) -> String {
        guard let grouping = locale.groupingSeparator, !grouping.isEmpty else { return text }
        return text.replacingOccurrences(of: grouping, with: "")
    }

    /// The typed text rewritten in `locale`'s own convention, ungrouped, or
    /// `Refused` when its separators have no one reading.
    static func normalized(_ raw: String, locale: Locale, integer: Bool = false) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let decimal = locale.decimalSeparator ?? "."
        let separators = text.filter { $0 == "." || $0 == "," }
        guard let last = separators.last else { return text }
        if !integer && separators.count == 1 {
            return text.replacingOccurrences(of: String(last), with: decimal)
        }
        // Several separators, or any in an integer: all but a decimal point
        // must be grouping, and grouping must be well formed.
        let point: Character? = integer || Set(separators).count == 1 ? nil : last
        let grouping: Character = point.map { $0 == "." ? "," : "." } ?? last
        let whole = point.map { p in String(text[..<text.lastIndex(of: p)!]) } ?? text
        guard !whole.contains(where: { $0 == point }) else { throw Refused() }
        let groups = whole.drop { $0 == "-" || $0 == "+" || $0 == "\u{2212}" }
            .split(separator: grouping, omittingEmptySubsequences: false)
        guard groups.count > 1, (1...3).contains(groups[0].count),
              groups.dropFirst().allSatisfy({ $0.count == 3 }),
              groups.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { throw Refused() }
        let ungroupedText = text.filter { $0 != grouping }
        return point.map { ungroupedText.replacingOccurrences(of: String($0), with: decimal) } ?? ungroupedText
    }
}

/// Edits typed into a `NumberEntryField` and not yet committed. Every UI
/// action that starts work goes through `run`, which commits them first —
/// the SwiftUI stand-in for AppKit's `commitEditing()`.
@MainActor
public enum PendingEdits {
    private static var commits: [UUID: () -> Void] = [:]

    public static func register(_ id: UUID, commit: @escaping () -> Void) { commits[id] = commit }
    public static func forget(_ id: UUID) { commits[id] = nil }

    public static func commitAll() {
        let pending = commits
        commits.removeAll()
        for commit in pending.values { commit() }
    }

    /// Commit every pending edit, then start `work`.
    public static func run(_ work: @escaping @MainActor () async -> Void) {
        commitAll()
        Task { await work() }
    }
}

/// The one text field every number is typed into: it owns its text and
/// commits on Return or focus loss — never per keystroke. Drive 2026-09-30:
/// SwiftUI's `TextField(value:format:)` committed each parseable prefix as it
/// was typed, so `0.0` on the way to `0.02` cleared the file's Q (the setter's
/// ≤ 0 branch) and a typo ended at its last good prefix (`300.5.` → 300,5).
/// A committed text that does not parse reverts; an empty one reverts, or
/// clears the value when `emptyClears`.
public struct NumberEntryField<Value: Equatable, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let title: String
    let value: Value?
    let format: Format
    var prompt: String?
    var emptyClears = false
    /// The field takes keyboard focus when it appears (a readout that turns into a field on a click: the next keystrokes
    /// are its own, drive 2026-10-07). Off, as everywhere else, for a field in a form.
    var focusOnAppear = false
    /// Called after every commit or cancel (Return, blur, Escape), whether or not a value was set: the owner of a transient
    /// field takes it away again.
    var onFinish: (() -> Void)?
    let onCommit: (Value?) -> Void

    public init(title: String, value: Value?, format: Format, prompt: String? = nil, emptyClears: Bool = false,
                focusOnAppear: Bool = false, onFinish: (() -> Void)? = nil, onCommit: @escaping (Value?) -> Void) {
        self.title = title
        self.value = value
        self.format = format
        self.prompt = prompt
        self.emptyClears = emptyClears
        self.focusOnAppear = focusOnAppear
        self.onFinish = onFinish
        self.onCommit = onCommit
    }

    @State private var text = ""
    @State private var editID = UUID()
    /// The user typed since the field last set its text from `value` (appear, an outside change, a commit, Escape).
    /// Only then is the shown text an edit (`resolve`'s `edited`).
    @State private var edited = false
    @FocusState private var isFocused: Bool

    private var entry: DecimalEntryFormat<Format> { DecimalEntryFormat(format) }
    private var shown: String { value.map { entry.format($0) } ?? "" }

    public var body: some View {
        TextField(title, text: $text, prompt: prompt.map { Text($0) })
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            // Escape abandons the edit, as in any Mac text field.
            .onExitCommand { PendingEdits.forget(editID); refresh(); onFinish?() }
            .onAppear {
                refresh()
                // After the field is in the window: a focus set in the same pass is dropped.
                if focusOnAppear { DispatchQueue.main.async { isFocused = true } }
            }
            // Torn down mid-edit (task or room switch): the edit still lands.
            .onDisappear(perform: commit)
            // Only a commit or an outside change moves `value` now, so the
            // text follows it even while the field keeps focus.
            .onChange(of: value) { _, _ in refresh() }
            // A click on a toolbar or inspector button does not take focus
            // from a Mac text field, so an uncommitted edit is registered and
            // every action that starts work commits it first
            // (`PendingEdits.run`, Fable review 2026-09-30).
            .onChange(of: text) { _, typed in
                // Only typing makes the text differ from `shown`: `refresh` sets it equal and clears `edited`. Once
                // typed, the shown text retyped is an edit too (MacEMUI#42).
                if typed != shown { edited = true }
                if !edited {
                    PendingEdits.forget(editID)
                } else {
                    PendingEdits.register(editID) { [value, emptyClears, entry, onCommit] in
                        if case .set(let newValue) = Self.resolve(typed: typed, current: value,
                                                                  emptyClears: emptyClears, entry: entry,
                                                                  edited: true) {
                            onCommit(newValue)
                        }
                    }
                }
            }
    }

    private func commit() {
        PendingEdits.forget(editID)
        if case .set(let newValue) = Self.resolve(typed: text, current: value,
                                                  emptyClears: emptyClears, entry: entry, edited: edited) {
            onCommit(newValue)
        }
        refresh()
        onFinish?()
    }

    /// The text follows `value` again; nothing is typed.
    private func refresh() {
        edited = false
        text = shown
    }

    nonisolated enum Resolution: Equatable { case keep, set(Value?) }

    /// What a committed text does — pure, so the rule is testable without a
    /// host: empty keeps (or clears, when `emptyClears`); the text the field
    /// shows for the current value, left untouched, keeps; a text that does not parse keeps; the
    /// same value keeps (no provenance flip); else sets.
    ///
    /// The shown text is not an edit: the field commits on
    /// blur, Return and teardown, and a format that shows fewer digits than the
    /// value has (a Defocus of 12.346 shown 12,3; a Float-backed 0.3, which is
    /// 0.30000001) would otherwise store its own rounding every time the field
    /// was merely left — and an Exploratory scale dragged to 0.0125597 lost its
    /// ACOM result to the 0.0126 it showed. So the shown text keeps only when
    /// the user did not type (`edited` false): typed over a finer value, the
    /// same text sets the number it reads as (0.0126 typed over 0.0125597
    /// sets 0.0126), MacEMUI#42.
    nonisolated static func resolve(typed raw: String, current: Value?, emptyClears: Bool,
                        entry: DecimalEntryFormat<Format>, edited: Bool = false) -> Resolution {
        let typed = raw.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return emptyClears && current != nil ? .set(nil) : .keep }
        if !edited, let current, typed == entry.format(current) { return .keep }
        guard let parsed = try? entry.parseStrategy.parse(typed), parsed != current else { return .keep }
        return .set(parsed)
    }
}
