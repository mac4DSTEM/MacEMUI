import AppKit
import XCTest
@testable import ShellLayout

/// The status bar's elapsed / throughput / ETA line: what it says, and the
/// slot it says it in.
///
/// The slot is the part that matters. The first version of this feature was
/// reverted the day it was written because its text carried `.fixedSize()`
/// and re-measured itself every second, which is the constraint loop that
/// aborted the app 2.5 minutes into a disk detection on a real dataset
/// (mac4DSTEM `docs/open-items.md`). The width is therefore a claim under test, not a
/// taste: the longest line the formatter can produce inside the bound this
/// test names must fit the reserved width, so the text truncates rather than
/// resizing its container.
nonisolated final class OperationMetricsFormatTests: XCTestCase {
    /// The formats print the reader's decimal mark (`locale: .autoupdatingCurrent`); the expectations are written with a point and follow the locale.
    private func local(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: Locale.autoupdatingCurrent.decimalSeparator ?? ".")
    }

    // MARK: - What the line says

    func testEachNumberAppearsOnlyOnceTheRunHasMeasuredIt() {
        XCTAssertEqual(OperationMetricsFormat.line(elapsed: 53, eta: nil), "53 s")

        // Throughput left this line on 2026-09-12 and is the inspector's
        // alone. A measured rate is not an input to this line any more (the
        // apps' old `unitsPerSecond: 78.8, eta: nil` case prints just the time).
        XCTAssertEqual(OperationMetricsFormat.line(elapsed: 150, eta: nil), "2:30")

        let full = OperationMetricsFormat.line(elapsed: 150, eta: 155)
        XCTAssertEqual(full, "2:30 · ETA 2:35")
        XCTAssertFalse(full.contains("/s"))
    }

    /// The unit follows what the app says the operation walks (patterns, positions); the app owns that rule
    /// (`throughputUnit(for:)` stays in mac4DSTEM), the formatter prints rate and unit.
    func testTheThroughputPrintsRateAndTheUnitItIsGiven() {
        XCTAssertEqual(OperationMetricsFormat.throughput(12.0, unit: "patterns/s"), local("12.0 patterns/s"))
        XCTAssertEqual(OperationMetricsFormat.throughput(12.0, unit: "positions/s"), local("12.0 positions/s"))
    }

    /// A rate of zero reads as a stall and an ETA the run cannot estimate is
    /// a number the user would plan around. Both are absent instead.
    func testAnUnmeasuredRunPrintsOnlyItsElapsedTime() {
        let line = OperationMetricsFormat.line(elapsed: 0, eta: nil)
        XCTAssertEqual(line, "0 s")
        XCTAssertFalse(line.contains("ETA"))
        XCTAssertFalse(line.contains("/s"))
    }

    func testDurationCountsMinutesPastAnHour() {
        XCTAssertEqual(OperationMetricsFormat.duration(59.4), "59 s")
        XCTAssertEqual(OperationMetricsFormat.duration(60), "1:00")
        XCTAssertEqual(OperationMetricsFormat.duration(7199), "119:59")
        XCTAssertEqual(OperationMetricsFormat.duration(-5), "0 s")
    }

    func testLastRunWordsCancelDifferently() {
        XCTAssertEqual(OperationMetricsFormat.lastRun("Disk detection", elapsed: 53, cancelled: false),
                       "Disk detection — 53 s")
        XCTAssertEqual(OperationMetricsFormat.lastRun("Disk detection", elapsed: 150, cancelled: true),
                       "Disk detection — cancelled after 2:30")
    }

    // MARK: - The slot it says it in

    /// The bound this test defends: **a hundred hours** in both fields.
    ///
    /// The sweep deliberately runs past an hour, and that is the point. The
    /// version of this test that stood until 2026-09-12 stopped at 59:59 in
    /// each field, which was enough while throughput dominated the width — and
    /// would have been exactly the wrong bound afterwards, because with the
    /// rate gone the two DURATIONS are what grows the string, and
    /// `duration(_:)` keeps counting minutes rather than growing an hours
    /// field. Narrowing the sweep to fit a smaller constant would be fitting
    /// the gate to the answer.
    func testTheReservedSlotFitsTheLongestLineTheFormatterProduces() {
        let font = statusBarFont()
        var widest = (line: "", width: CGFloat(0))

        for elapsed in [0.0, 53, 150, 59 * 60 + 59, 5999 * 60 + 59] as [TimeInterval] {
            for eta in [nil, 5, 155, 59 * 60 + 59, 5999 * 60 + 59] as [TimeInterval?] {
                let line = OperationMetricsFormat.line(elapsed: elapsed, eta: eta)
                let width = (line as NSString)
                    .size(withAttributes: [.font: font]).width
                if width > widest.width { widest = (line, width) }
            }
        }

        XCTAssertLessThanOrEqual(
            widest.width, LayoutPolicy.operationReadoutWidth,
            """
            The widest line the formatter can produce inside the documented \
            bound is "\(widest.line)" at \(widest.width) pt, which does not \
            fit LayoutPolicy.operationReadoutWidth \
            (\(LayoutPolicy.operationReadoutWidth) pt). Widen the constant — \
            do NOT let the text size itself.
            """
        )
    }

    /// The toolbar's busy line takes the reserved slot (it is the one place that draws the clock).
    func testTheToolbarsClockTakesTheReservedSlot() {
        XCTAssertEqual(ToolbarRunDisplay.metricsWidth, LayoutPolicy.operationReadoutWidth)
    }

    /// `.subheadline.monospacedDigit()`, which is what the toolbar's busy line draws in (`ToolbarRunDisplay.busyFont`).
    /// Measured rather than assumed: the constant above is only defensible
    /// against the font that actually renders it.
    private func statusBarFont() -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: .subheadline)
        return NSFont.monospacedDigitSystemFont(
            ofSize: base.pointSize, weight: .regular
        )
    }

    /// The infobar's live run (owner, 2026-09-22 late): done / total, the
    /// rate, elapsed and ETA in one line; a part not known yet is absent.
    func testTheRunLineJoinsCountsRateAndTimesAndOmitsWhatIsUnknown() {
        XCTAssertEqual(
            OperationMetricsFormat.runLine(done: 1204, total: 4050, elapsed: 53, eta: 42, rate: 312.4, unit: "positions/s"),
            "\(SystemMonitor.count(1204)) / \(SystemMonitor.count(4050)) · \(local("312.4")) positions/s · 53 s · ETA 42 s")
        XCTAssertEqual(
            OperationMetricsFormat.runLine(done: nil, total: nil, elapsed: 3, eta: nil, rate: nil, unit: "positions/s"),
            "3 s")
    }

    /// The glance is Finder-style (1000-based): 1000 decimal MB is local("1.0 GB"), not "1000 MB". The residency
    /// word is mac4DSTEM's; the plain figure is both apps'.
    func testGlanceUsesTheDecimalBase() {
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 1000, residency: true), local("1.0 GB · resident"))
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 999, residency: false), "999 MB · streaming")
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 16965, residency: true), local("17.0 GB · resident"))
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 1_200_000, residency: true), local("1.2 TB · resident"))
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 1000), local("1.0 GB"))
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 612), "612 MB")
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 1_000_000), local("1.0 TB"))
    }

    /// `runReadoutWidth` is measured, not chosen: the widest run line the
    /// formatter can produce at the infobar's 12-pt monospaced digits must
    /// fit the slot, so a ticking string never resizes its own container.
    func testTheRunReadoutSlotFitsTheLongestRunLine() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
        var widest = (line: "", width: CGFloat(0))
        for unit in ["positions/s", "patterns/s"] {
            for (done, total) in [(0, 144), (1204, 4050), (9_999_999, 9_999_999)] {
                for rate in [nil, 0.1, 999.9, 9999.9] as [Double?] {
                    for eta in [nil, 5, 5999 * 60 + 59] as [TimeInterval?] {
                        let line = OperationMetricsFormat.runLine(
                            done: done, total: total,
                            elapsed: 5999 * 60 + 59, eta: eta, rate: rate, unit: unit)
                        let width = (line as NSString).size(withAttributes: [.font: font]).width
                        if width > widest.width { widest = (line, width) }
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(widest.width, LayoutPolicy.runReadoutWidth,
            "\"\(widest.line)\" is \(widest.width) pt; widen LayoutPolicy.runReadoutWidth — do NOT let the text size itself.")
    }
}
