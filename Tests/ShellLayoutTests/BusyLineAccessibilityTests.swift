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

    @MainActor private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
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
        let start = Date()
        let metrics: (Date) -> (elapsed: TimeInterval, eta: TimeInterval?)? = { date in
            (elapsed: date.timeIntervalSince(start), eta: nil)
        }
        let (window, root) = host(ToolbarRunDisplay(.busy(operation: "Disk detection", progress: 0.2, metrics: metrics)))
        defer { window.close() }
        spin(0.3)
        let first = try XCTUnwrap(elements("toolbar.display.busy", in: root).first, "no busy line element")
        XCTAssertEqual(first.accessibilityLabel(), "Disk detection · 0 s")
        XCTAssertEqual(first.accessibilityValue() as? String, "20 percent")
        spin(2.2)
        let found = elements("toolbar.display.busy", in: root)
        XCTAssertEqual(found.count, 1, "one element, kept across ticks")
        let later = try XCTUnwrap(found.first)
        let label = try XCTUnwrap(later.accessibilityLabel())
        let elapsed = Date().timeIntervalSince(start)
        // The label is the last tick drawn: whole seconds, at most one behind now.
        let expected = [Int(elapsed.rounded(.down)) - 1, Int(elapsed.rounded(.down))].map {
            ToolbarDisplayFormat.busy(operation: "Disk detection", elapsed: TimeInterval($0), eta: nil)
        }
        XCTAssertTrue(expected.contains(label), "label \"\(label)\" after \(elapsed) s, expected one of \(expected)")
        XCTAssertNotEqual(label, "Disk detection · 0 s")
    }

    /// The infobar readout the same way: its label is the line of the last tick.
    @MainActor func testTheInfobarReadoutLabelFollowsTheTicks() throws {
        let start = Date()
        let line: (Date) -> String = { date in "\(Int(date.timeIntervalSince(start))) s" }
        let (window, root) = host(InfobarRunReadout(operation: "Disk detection", progress: 0.2, line: line, onCancel: nil))
        defer { window.close() }
        spin(0.3)
        let first = try XCTUnwrap(elements("status.footer.metrics", in: root).first, "no readout element")
        XCTAssertEqual(first.accessibilityLabel(), "0 s")
        spin(2.2)
        let label = try XCTUnwrap(elements("status.footer.metrics", in: root).first?.accessibilityLabel())
        XCTAssertNotEqual(label, "0 s", "the readout kept its first tick")
    }
}
