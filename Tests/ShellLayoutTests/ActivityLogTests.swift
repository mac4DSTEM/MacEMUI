import Foundation
import Observation
import XCTest
@testable import ShellLayout

/// The output strip's log, and the one thing about it that fails silently.
nonisolated final class ActivityLogTests: XCTestCase {

    // MARK: - The log is observed, or the strip quietly stops

    /// **The reason this extraction is worth doing, and the only mutation that
    /// matters.** The output strip reads `activityLog.messages` and scrolls on
    /// its newest id. If `ActivityLog` is not `@Observable`, every other test here still passes,
    /// the app still builds, and the strip simply never updates again — the
    /// exact shape of silent failure this repo keeps paying for.
    ///
    /// So this asserts the chain a view depends on, in a pure XCTest
    /// with no UI and no Metal: `record` must notify an
    /// observer of `messages`. Break it by deleting `@Observable`
    /// from `ActivityLog`. (In mac4DSTEM the same test drives it through
    /// `AppState.statusText`; that one stays in the app.)
    @MainActor func testRecordingNotifiesAnObserverOfTheLog() {
        let log = ActivityLog()
        // A nonisolated reference box, not a captured `var`: `onChange` runs
        // outside this actor, and mutating main-actor state there is an error
        // under the Swift 6 language mode.
        let flag = ObservationFlag()
        withObservationTracking {
            _ = log.messages
        } onChange: {
            flag.fired = true
        }

        log.record("a message the log must carry")

        XCTAssertTrue(flag.fired, "the output strip stops updating if this seam is not observed")
    }

    // MARK: - What it records, and what it refuses

    /// The log half of the funnel rule: the old rule was "a message ending in %", which forced every operation
    /// to append a percentage to its status line purely to be filtered. The status-string half (50 progress
    /// ticks through `updateCancellableOperation` write no lines) needs the app's state and stays in the app.
    @MainActor func testProgressSpamAndEmptyMessagesNeverReachTheLog() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        log.record("")
        log.record("Detecting disks… 42 %")
        log.record("Detecting disks… 100 %")
        XCTAssertTrue(log.messages.isEmpty,
                      "a percentage tick is progress, not an event: \(log.messages)")

        log.record("Disks ✓ 16384 peaks")
        XCTAssertEqual(log.messages.count, 1)
    }

    /// A status written twice is one thing happening.
    @MainActor func testAnImmediateRepeatIsNotStacked() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        log.record("Loaded WS2.h5")
        log.record("Loaded WS2.h5")
        XCTAssertEqual(log.messages.count, 1)

        log.record("Something else")
        log.record("Loaded WS2.h5")
        XCTAssertEqual(log.messages.count, 3, "a repeat that is not immediate is a real event")
    }

    @MainActor func testTheLogIsCappedAndKeepsTheNewestLines() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        for i in 0..<(ActivityLog.capacity + 50) { log.record("line \(i)") }

        XCTAssertEqual(log.messages.count, ActivityLog.capacity)
        XCTAssertTrue(log.messages.last?.hasSuffix("line \(ActivityLog.capacity + 49)") == true,
                      "the newest line survives")
        XCTAssertFalse(log.messages.contains { $0.hasSuffix("line 0") },
                       "the oldest lines are the ones dropped")
    }

    /// At capacity a new line must still produce a new newest id (the strip
    /// scrolls on it; the count no longer moves), ids must be unique, and a
    /// surviving line keeps the id it had. Mutation: `Line.id` taken from the
    /// position (index) instead of the monotonic counter -> red.
    @MainActor func testActivityLogIdsStayUniqueAndStableAtCapacity() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        for i in 0..<ActivityLog.capacity { log.record("line \(i)") }
        XCTAssertEqual(log.lines.count, ActivityLog.capacity)

        let before = log.lines
        let lastBefore = before.last?.id
        let survivor = before[ActivityLog.capacity / 2]

        log.record("one more")
        XCTAssertEqual(log.lines.count, ActivityLog.capacity, "still at the cap")
        XCTAssertNotEqual(log.lines.last?.id, lastBefore, "a new line yields a new newest id")
        XCTAssertEqual(Set(log.lines.map(\.id)).count, ActivityLog.capacity, "ids are unique")
        XCTAssertTrue(log.lines.contains(survivor), "a surviving line keeps its id and text")

        log.clear()
        log.record("after clear")
        XCTAssertFalse(before.map(\.id).contains(log.lines[0].id), "ids are not reused after clear")
    }

    // MARK: - Where the output strip scrolls to

    /// The output strip scrolls on `.onChange` of the newest line's id, which
    /// never fires the first time the panel appears — it opens scrolled to its
    /// top instead of its newest line. The fix reads this pure rule on
    /// `.onAppear` too, so it has to be right for a log with nothing in it
    /// as well as one already full.
    @MainActor func testScrollTargetIsTheNewestLineIdOrNilWhenEmpty() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        XCTAssertNil(ActivityLog.scrollTarget(for: log.lines))
        log.record("one")
        XCTAssertEqual(ActivityLog.scrollTarget(for: log.lines), log.lines.last?.id)
        for i in 0..<(ActivityLog.capacity + 5) { log.record("line \(i)") }
        XCTAssertEqual(ActivityLog.scrollTarget(for: log.lines), log.lines.last?.id)
    }

    /// The stamp is the injected clock's, not the wall clock's.
    @MainActor func testEachLineCarriesTheTimeItWasRecorded() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let log = ActivityLog(now: { now })
        let stamp = { (d: Date) -> String in
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
        }

        log.record("first")
        now.addTimeInterval(3661)
        log.record("second")

        XCTAssertTrue(log.messages[0].hasPrefix(stamp(Date(timeIntervalSinceReferenceDate: 0))))
        XCTAssertTrue(log.messages[1].hasPrefix(stamp(now)))
        XCTAssertNotEqual(String(log.messages[0].prefix(8)), String(log.messages[1].prefix(8)))
    }

    /// A READOUT IS NOT AN EVENT, and before 2026-09-12 the log could not tell
    /// the difference. Every click on the scan image wrote
    /// "Pattern x 154, y 152 from <filename>" through `statusText`, the
    /// consecutive-repeat rule never fired because the coordinates differ
    /// every time, and on a 330 × 330 scan there are 108 900 of them against a
    /// 300-line capacity — so moving the cursor evicted the run's real events
    /// from the record kept to explain them. Observed in the owner's own
    /// screenshot.
    ///
    /// Mutation: `suppressNextRecord` never reset, or read without being
    /// consumed. Either one makes the flag leak into the write after it, and
    /// the first real event following a click would vanish instead.
    @MainActor func testAReadoutReachesTheStatusLineAndNotTheLog() {
        let log = ActivityLog(now: { Date(timeIntervalSince1970: 0) })
        log.record("Disks ✓ 802 752 peaks")
        XCTAssertEqual(log.messages.count, 1)

        log.suppressNextRecordOnce()
        log.record("Pattern x 154, y 152")
        XCTAssertEqual(log.messages.count, 1, "a readout was recorded as an event")

        // Consumed: the very next write is an event again.
        log.record("Pattern x 96, y 80")
        XCTAssertEqual(log.messages.count, 2,
                       "the suppression leaked into the write after it")
        XCTAssertTrue(log.messages.last?.hasSuffix("Pattern x 96, y 80") ?? false)

        // And suppressing then recording nothing must not arm the next write.
        log.suppressNextRecordOnce()
        log.record("")
        log.record("Phase map: β″ 1, matrix 0")
        XCTAssertEqual(log.messages.count, 3,
                       "an empty suppressed write left the flag armed")
    }

    // MARK: - The clock

    /// The status clock: fixed "HH:mm:ss" (24-hour in both locales), midnight, noon, late, single digits.
    /// (From mac4DSTEM's FormatStyleMigrationTests, "ActivityLog's status clock".)
    @MainActor func testActivityLogClockIsUnchanged() {
        let utc = TimeZone(identifier: "UTC")!
        let en = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
        let instants = ["2026-10-08T00:00:00Z", "2026-10-08T12:00:05Z", "2026-10-08T14:03:22Z",
                        "2026-10-08T23:59:59Z", "2026-01-05T09:07:03Z"]
        let enStrings = ["00:00:00", "12:00:05", "14:03:22", "23:59:59", "09:07:03"]
        for (iso, expected) in zip(instants, enStrings) {
            XCTAssertEqual(ActivityLog.clockText(instant(iso), locale: en, timeZone: utc), expected, "en_US \(iso)")
            XCTAssertEqual(ActivityLog.clockText(instant(iso), locale: de, timeZone: utc), expected, "de_DE \(iso)")
        }
    }
}

/// Set from `withObservationTracking`'s `onChange`, which runs off the main
/// actor. Nonisolated on purpose; see its one use above.
nonisolated final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var fired: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }

}
