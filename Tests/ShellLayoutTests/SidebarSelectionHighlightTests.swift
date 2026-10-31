// The rooms list as the table draws it (MacEMUI#49): a room row whose selection is disabled must not keep its highlight
// when the selection moves to another room. SwiftUI's own selection state does not show the fault, so these tests host the
// list in a window and read the table's selected rows, which is what the sidebar paints.

import AppKit
import SwiftUI
import XCTest
@testable import ShellLayout

private nonisolated enum HighlightRoom: String, CaseIterable, WorkspaceRoom {
    case prepare, image, edx

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbolName: String { "circle" }
    var subtitle: String { "The \(rawValue) room" }
}

/// The app side: which room is selected and which rooms hold data, as macTEM keeps them.
@Observable private final class HighlightModel {
    var selection: HighlightRoom? = .image
    var unavailable: Set<HighlightRoom> = []
}

private struct HighlightSidebar: View {
    @Bindable var model: HighlightModel

    var body: some View {
        WorkspaceSidebarFrame(selection: $model.selection) {
            WorkspaceRoomsSection(rooms: HighlightRoom.allCases, tag: { $0 },
                                  isAvailable: { !model.unavailable.contains($0) })
        }
        .frame(width: 220, height: 300)
    }
}

nonisolated final class SidebarSelectionHighlightTests: XCTestCase {

    @MainActor private final class Host {
        let model = HighlightModel()
        let window: NSWindow

        init() {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HighlightSidebar(model: model))
            settle()
        }

        /// Lets SwiftUI apply its pending updates to the table.
        func settle() {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            window.contentView?.layoutSubtreeIfNeeded()
        }

        /// The rooms whose rows the table draws selected. The table's rows are the section header, then the rooms in order.
        var highlighted: [String] {
            guard let table = Self.table(in: window.contentView) else { return ["no table"] }
            let rooms = HighlightRoom.allCases
            let first = table.numberOfRows - rooms.count
            return table.selectedRowIndexes.map { row in
                rooms.indices.contains(row - first) ? rooms[row - first].rawValue : "row \(row)"
            }
        }

        private static func table(in view: NSView?) -> NSTableView? {
            guard let view else { return nil }
            if let table = view as? NSTableView { return table }
            for sub in view.subviews { if let found = table(in: sub) { return found } }
            return nil
        }

        func close() { window.close() }
    }

    /// macTEM, a lone .msa: Image is selected, loses its data, and the route moves to EDS in the same update.
    @MainActor func testTheRouteLeavingARoomThatJustBecameUnavailableHighlightsOnlyTheNewRoom() {
        let host = Host()
        defer { host.close() }
        XCTAssertEqual(host.highlighted, ["image"])
        host.model.unavailable = [.image]
        host.model.selection = .edx
        host.settle()
        XCTAssertEqual(host.highlighted, ["edx"])
    }

    /// The same, with the room disabled first and the selection moved in a later update.
    @MainActor func testTheSelectionLeavingASelectedUnavailableRoomHighlightsOnlyTheNewRoom() {
        let host = Host()
        defer { host.close() }
        host.model.unavailable = [.image]
        host.settle()
        host.model.selection = .edx
        host.settle()
        XCTAssertEqual(host.highlighted, ["edx"])
    }

    /// A room that becomes available again can be highlighted again.
    @MainActor func testARoomThatReturnsCanBeSelectedAgain() {
        let host = Host()
        defer { host.close() }
        host.model.unavailable = [.image]
        host.model.selection = .edx
        host.settle()
        host.model.unavailable = []
        host.model.selection = .image
        host.settle()
        XCTAssertEqual(host.highlighted, ["image"])
    }
}
