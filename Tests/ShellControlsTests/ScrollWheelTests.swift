import XCTest
@testable import ShellControls

nonisolated final class ScrollWheelTests: XCTestCase {
    /// A point inside or on the edge is accepted; outside is not.
    func testRoutingAcceptsInsideAndEdgeOnly() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertTrue(ScrollWheelRouting.accepts(point: CGPoint(x: 40, y: 20), in: bounds))
        XCTAssertTrue(ScrollWheelRouting.accepts(point: CGPoint(x: 100, y: 0), in: bounds))
        XCTAssertFalse(ScrollWheelRouting.accepts(point: CGPoint(x: 100.5, y: 20), in: bounds))
        XCTAssertFalse(ScrollWheelRouting.accepts(point: CGPoint(x: 40, y: -1), in: bounds))
    }
}
