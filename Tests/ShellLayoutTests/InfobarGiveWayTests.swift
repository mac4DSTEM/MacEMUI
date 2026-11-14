import XCTest
@testable import ShellLayout

/// The infobar's give-way order in a narrow window (Paul, 2026-11-14): the task words keep their width; the run line drops ETA, then
/// elapsed, then the count.
nonisolated final class InfobarGiveWayTests: XCTestCase {
    /// Mutation: the parts dropped from the front -> red (the count goes first).
    func testTheRunLineDropsETAThenElapsedThenTheCount() {
        let line = OperationMetricsFormat.runLine(done: 800, total: 160_000, elapsed: 3, eta: 22, rate: nil, unit: "patterns")
        let lines = OperationMetricsFormat.runLineFallbacks(line)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], line)
        XCTAssertTrue(lines[0].contains("ETA"))
        XCTAssertFalse(lines[1].contains("ETA"))
        XCTAssertTrue(lines[1].hasPrefix(lines[2] + " · "))
        XCTAssertEqual(lines[2], "\(SystemMonitor.count(800)) / \(SystemMonitor.count(160_000))")
        XCTAssertEqual(lines[3], "")
    }

    func testALineWithoutTimesFallsBackToTheCountThenNothing() {
        XCTAssertEqual(OperationMetricsFormat.runLineFallbacks("0 / 10"), ["0 / 10", ""])
        XCTAssertEqual(OperationMetricsFormat.runLineFallbacks(""), [""])
    }

    /// Mutation: the run's priority back above the status words while running -> red.
    func testTheTaskWordsOutlastTheRunNumbersAndTheGlanceGivesWayFirst() {
        let running = LayoutPolicy.infobarPriorities(isRunning: true)
        XCTAssertGreaterThan(running.status, running.run)
        XCTAssertGreaterThan(running.run, running.glance)
        let idle = LayoutPolicy.infobarPriorities(isRunning: false)
        XCTAssertGreaterThan(idle.status, idle.run)
    }
}
