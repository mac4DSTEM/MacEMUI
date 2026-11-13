//
//  NonFiniteProgressTests.swift
//  A NaN or infinite ETA or progress is written, never `Int(NaN)` (MacEMUI#124). Red before: `duration(.infinity)` (an ETA from a
//  zero rate) and `Int(NaN * 100)` trapped on every toolbar tick.
//

import XCTest
@testable import ShellLayout

nonisolated final class NonFiniteProgressTests: XCTestCase {

    func testANaNOrInfiniteDurationIsWrittenNotTrapped() {
        XCTAssertEqual(OperationMetricsFormat.duration(.nan), "–")
        XCTAssertFalse(OperationMetricsFormat.duration(.infinity).isEmpty)
        XCTAssertEqual(OperationMetricsFormat.duration(-.infinity), "0 s")
        XCTAssertEqual(OperationMetricsFormat.duration(53), "53 s")
        XCTAssertEqual(OperationMetricsFormat.duration(155), "2:35")
    }

    func testANaNOrInfiniteProgressSpeaksNothing() {
        XCTAssertEqual(OperationMetricsFormat.percent(.nan), "")
        XCTAssertEqual(OperationMetricsFormat.percent(.infinity), "")
        XCTAssertEqual(OperationMetricsFormat.percent(nil), "")
        XCTAssertEqual(OperationMetricsFormat.percent(0.374), "37 percent")
        XCTAssertEqual(OperationMetricsFormat.percent(1.5), "100 percent")
    }
}
