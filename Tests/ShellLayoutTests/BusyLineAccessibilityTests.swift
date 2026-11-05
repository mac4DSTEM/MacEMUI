// The ticking readouts as an accessibility client reads them: hosted in a window, ticked by their own TimelineView, read
// after two ticks (MacEMUI#39: the label kept the first second, "0 s", while the screen drew 13 s).

import AppKit
import SwiftUI
import XCTest
@testable import ShellLayout

nonisolated final class BusyLineAccessibilityTests: XCTestCase {

    /// The accessibility elements in `root`'s view tree whose identifier is `id`. SwiftUI builds its own accessibility
    /// nodes only for a live accessibility client, so a unit test reaches the element only when it is a view.
    @MainActor private func elements(_ id: String, in root: NSView) -> [NSView] {
        var found: [NSView] = []
        if root.isAccessibilityElement(), root.accessibilityIdentifier() == id { found.append(root) }
        for child in root.subviews { found += elements(id, in: child) }
        return found
    }

    /// The test's clock: the readouts ask it for the elapsed time at each tick, and it answers what the test set, never
    /// the wall clock, so a loaded machine that ticks late cannot change what the label should say (MacEMUI#75).
    @MainActor private final class TestClock {
        var elapsed: TimeInterval = 0
    }

    /// Runs the main run loop until `done` holds or `timeout` passes (the readouts tick once a second, so a few seconds
    /// is generous even on a loaded runner). Returns whether `done` held.
    @MainActor @discardableResult
    private func spin(until done: () -> Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return done()
    }

    @MainActor private func host<V: View>(_ view: V) -> (NSWindow, NSView) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 80), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return (window, host)
    }

    /// Two seconds into a run the busy line says what it draws: "Disk detection · 2 s", not the first tick's "0 s".
    @MainActor func testTheBusyLineLabelFollowsTheTicks() throws {
        let clock = TestClock()
        let metrics: (Date) -> (elapsed: TimeInterval, eta: TimeInterval?)? = { _ in (elapsed: clock.elapsed, eta: nil) }
        let (window, root) = host(ToolbarRunDisplay(.busy(operation: "Disk detection", progress: 0.2, metrics: metrics)))
        defer { window.close() }
        spin(until: { !self.elements("toolbar.display.busy", in: root).isEmpty })
        let first = try XCTUnwrap(elements("toolbar.display.busy", in: root).first, "no busy line element")
        XCTAssertEqual(first.accessibilityLabel(), "Disk detection · 0 s")
        XCTAssertEqual(first.accessibilityValue() as? String, "20 percent")
        clock.elapsed = 2
        let later = "Disk detection · 2 s"
        spin(until: { self.elements("toolbar.display.busy", in: root).first?.accessibilityLabel() == later })
        let found = elements("toolbar.display.busy", in: root)
        XCTAssertEqual(found.count, 1, "one element, kept across ticks")
        // The label is the tick drawn after the clock moved, not the first tick's "0 s".
        XCTAssertEqual(try XCTUnwrap(found.first).accessibilityLabel(), later)
    }

    /// The infobar readout the same way: its label is the line of the last tick.
    @MainActor func testTheInfobarReadoutLabelFollowsTheTicks() throws {
        let clock = TestClock()
        let line: (Date) -> String = { _ in "\(Int(clock.elapsed)) s" }
        let (window, root) = host(InfobarRunReadout(operation: "Disk detection", progress: 0.2, line: line, onCancel: nil))
        defer { window.close() }
        spin(until: { !self.elements("status.footer.metrics", in: root).isEmpty })
        let first = try XCTUnwrap(elements("status.footer.metrics", in: root).first, "no readout element")
        XCTAssertEqual(first.accessibilityLabel(), "0 s")
        clock.elapsed = 2
        spin(until: { self.elements("status.footer.metrics", in: root).first?.accessibilityLabel() == "2 s" })
        let label = try XCTUnwrap(elements("status.footer.metrics", in: root).first?.accessibilityLabel())
        XCTAssertEqual(label, "2 s", "the readout kept an earlier tick")
    }
}
