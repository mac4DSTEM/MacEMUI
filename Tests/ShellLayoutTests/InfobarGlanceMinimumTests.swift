import AppKit
import SwiftUI
import XCTest
@testable import ShellLayout

/// The memory glance never reports a minimum narrower than its icon (#139): the infobar sizes the run slot from that minimum, so a
/// floor under the icon put the icon beneath the run's Cancel at a narrow window.
nonisolated final class InfobarGlanceMinimumTests: XCTestCase {
    @MainActor private func width<V: View>(_ view: V, proposed: CGFloat) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: proposed, height: 100)).width
    }

    /// Mutation: the glance's `minWidth` back to `compressibleSlotMinimum` -> red (it reports 0 at a zero proposal).
    @MainActor func testTheGlanceKeepsRoomForItsIcon() {
        let icon = width(Image(systemName: "memorychip").font(.callout).fixedSize(), proposed: 10_000)
        XCTAssertGreaterThan(icon, 0)
        let squeezed = width(InfobarGlance { "Apple M5 Pro · 120 MB · streaming" }, proposed: 0)
        XCTAssertGreaterThanOrEqual(squeezed, icon)
        XCTAssertGreaterThanOrEqual(LayoutPolicy.statusGlanceMinimumWidth, icon)
    }
}
