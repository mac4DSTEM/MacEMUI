// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/App/ActivityLog.swift (macTEM@51c944c macTEM/App/ActivityLog.swift folded in: no differences; macTEM's copy is the same minus the AppState.showReadout extension)
// Changes: made public; Line made nonisolated and Sendable; the AppState.showReadout extension stays app-side
// END MOVED FROM
//
//  ActivityLog.swift
//  Role: The session's rolling record of what happened, shown in the output
//        strip along the bottom of the science panes.
//
//  An app-state seam (../_archive/mac4DSTEM/docs/archive/development-process-2026-08-31.md §7),
//  under CLAUDE.md's rule that a session touching the app state moves one
//  responsibility out of it. It is view-state with no science in it.
//
//  Views read `activityLog.messages`; no forwarding properties on the app state.
//
//  `@Observable` here is load-bearing, not ceremony: the output strip reads
//  `lines` and scrolls on the newest line's id, and without observation
//  the strip goes silently stale. `ActivityLogTests` pins the chain
//  with `withObservationTracking` rather than trusting the annotation.
//

import Foundation
import Observation

@Observable
public final class ActivityLog {
    /// One log line with an identity that belongs to the line, not to its
    /// position. At capacity the oldest line is dropped for every new one, so
    /// a position-keyed row (the old `id: \.offset`) changed identity on every
    /// line below the drop: all 300 rows re-rendered, a text selection landed
    /// on the neighbouring line, and the count-keyed auto-scroll stopped
    /// firing because the count stays 300.
    public nonisolated struct Line: Identifiable, Equatable, Sendable {
        /// Monotonic across the log's life (not reset by `clear`), so an id
        /// is never reused by a later line.
        public let id: Int
        public let text: String
    }

    /// Oldest first, newest last — the order the strip scrolls in.
    public private(set) var lines: [Line] = []

    /// The log as plain strings, for every caller that reads text only.
    public var messages: [String] { lines.map(\.text) }

    /// The next line's id. Not observed: only `lines` drives the view.
    @ObservationIgnored private var nextID = 0

    /// An unbounded log is a memory leak with a scroll bar. A long run writes
    /// thousands of lines and nobody reads past the last screenful.
    public static let capacity = 300

    /// Injected so a test can assert the stamp instead of asserting that the
    /// clock is a clock.
    @ObservationIgnored private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Set by the app's `showReadout` for the one write that follows it.
    ///
    /// A READOUT IS NOT AN EVENT. The status line has two jobs — reporting
    /// what happened, and showing where you are — and only the first belongs
    /// in a log. Without this, every click on the scan image writes "Pattern
    /// x 154, y 152 from <filename>" here; the dedupe below never fires
    /// because the coordinates differ every time, and a 330 × 330 scan has
    /// 108 900 of them against a 300-line capacity — cursor movement would
    /// evict the run's real events (detection, import, phase map) from the
    /// record kept to explain them (observed 2026-09-12).
    ///
    /// A one-shot flag, not an `isEvent:` parameter on `record`, because the
    /// caller is `statusText.didSet` and a `didSet` cannot see who wrote to it.
    @ObservationIgnored private var suppressNextRecord = false

    /// The next `record` is a readout and is dropped. Consumed either way, so
    /// a suppressed write cannot leak into the one after it.
    public func suppressNextRecordOnce() { suppressNextRecord = true }

    /// Empties the log. The bottom workspace's Output tab "Clear" button
    /// (ADR 034) — a deliberate user action, not a rule this file enforces
    /// on its own, so it is a plain removal with no suppression bookkeeping.
    public func clear() { lines.removeAll() }

    /// Record one status event.
    ///
    /// Three things never reach the log. A readout, per
    /// `suppressNextRecordOnce` above — the primary defence against progress
    /// spam, since the app's `updateCancellableOperation` is the one funnel
    /// every operation's progress passes through and it calls `showReadout`.
    /// An immediate repeat of the last message, because a status written twice
    /// is one thing happening, not two. And any message ending in "%", a
    /// backstop that is not sufficient alone: `SystemMonitor.scanProgressStatus`
    /// returns lines like "...1.54 GB of 1.66 GB", which end in "GB" not "%",
    /// so a whole-cube pass could still write a line per tick without the
    /// funnel (observed 2026-09-12). The suffix check stays as a second line
    /// of defence; no status string needs it any more since the progress bar
    /// beside them draws the percentage instead.
    public func record(_ message: String) {
        let suppressed = suppressNextRecord
        suppressNextRecord = false
        guard !suppressed else { return }
        guard !message.isEmpty, !message.hasSuffix("%") else { return }
        if lines.last?.text.hasSuffix(message) == true { return }
        lines.append(Line(id: nextID, text: "\(Self.clockText(now()))  \(message)"))
        nextID += 1
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }

    /// The status line's clock: "HH:mm:ss" in the person's locale and time zone (both injectable for the pins in `ActivityLogTests`).
    public static func clockText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            locale: locale, timeZone: timeZone, calendar: locale.calendar))
    }

    /// The row a `ScrollViewReader` should scroll to for these lines — the
    /// newest one's id, or none for an empty log. Pulled out so the output
    /// strip's `.onAppear` (the panel opening scrolled to the top instead of
    /// the newest line) and its `.onChange` of the newest id share one rule.
    /// The id, not the count: at capacity the count stops changing while the
    /// newest id keeps moving.
    public static func scrollTarget(for lines: [Line]) -> Int? {
        lines.last?.id
    }
}
