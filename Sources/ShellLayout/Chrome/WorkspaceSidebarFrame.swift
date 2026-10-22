// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/UI/WorkspaceSidebar.swift (the `List(selection:)` and its three modifiers; the Workspace section of rooms with its row, badge, help, identifiers and the withheld/disabled treatment) (macTEM@51c944c macTEM/UI/WorkspaceSidebar.swift folded in: unavailable rooms drawn in the tertiary style so they read as unavailable in every state, "not built yet" help)
// Changes: split: the chassis only, generic over `WorkspaceRoom`; the Dataset door, the Next hint, the task rows, the Spectroscopy tools, the Session section, macTEM's Open Files list and the removal dialog stay app-side as the `content` slot and ordinary modifiers
// END MOVED FROM

import SwiftUI

/// The left column: navigation and context only. A source list, not a settings pane: selection, hover, the row
/// capsule and `AXOutlineRow` all come from the `List` itself, tagged with the app's selection value (mac4DSTEM:
/// `WorkspaceRoute`, a room or a task or a tool; macTEM: the room), so selection binds straight onto the app's state.
///
/// The app composes the list's content in order, with `WorkspaceRoomsSection` where the rooms go: mac4DSTEM puts its
/// Dataset door section before it and its task rows and Session section after; macTEM puts only the rooms and shows
/// its Open Files list below this view (two lists, each with its own selection, so a file chosen does not drop the
/// active room's highlight).
public struct WorkspaceSidebarFrame<Selection: Hashable, Content: View>: View {
    private let selection: Binding<Selection?>
    private let content: Content

    public init(selection: Binding<Selection?>, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }

    public var body: some View {
        List(selection: selection) {
            content
        }
        .listStyle(.sidebar)
        // One material per column, and it is the system's — a `.sidebar` List
        // paints a second one inside the scroll view that composites
        // differently where the sidebar's own material already shows. No test
        // can see it (a hosted layout is blind to materials), so this line is
        // held by review and the drive. The row selection capsule is drawn by
        // the table, not by this background, so hiding it costs nothing
        // visible. The glass lives on the buttons, not on a floating pane: the
        // owner tried the pane (mac4DSTEM ADR 058 §5) and preferred the flat column.
        .scrollContentBackground(.hidden)
        // Bounce only when there is something to scroll, so elastic
        // overscroll can never park the clip origin above the top.
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// The "Workspace" section: one row per room, ⌘N in the app's menu, the unavailable ones listed but dimmed and not
/// selectable — the list keeps its rows and its shortcuts, and nothing leads into an empty room (mac4DSTEM: a 4D room
/// in a spectrum-only window; macTEM: a room not built yet).
public struct WorkspaceRoomsSection<Room: WorkspaceRoom, Selection: Hashable, Footer: View>: View {
    private let rooms: [Room]
    private let tag: (Room) -> Selection
    private let isAvailable: (Room) -> Bool
    private let unavailableHelp: (Room) -> String
    private let badge: (Room) -> Int
    private let footer: Footer

    /// - Parameters:
    ///   - rooms: In list order, which is also the ⌘N order.
    ///   - tag: The room's selection value in the enclosing list.
    ///   - isAvailable: Whether the room can be entered in this window. Default: the room's own `isAvailable`.
    ///   - unavailableHelp: The hover help of a room that cannot be entered ("Prepare works on a 4D-STEM scan; this
    ///     window holds a spectrum image only.").
    ///   - badge: A count as macOS carries one — a `.badge`, which hides itself at zero (mac4DSTEM: saved results
    ///     on Results).
    ///   - footer: Below the rooms, still in the section (mac4DSTEM's "Next: …" hint).
    public init(
        rooms: [Room],
        tag: @escaping (Room) -> Selection,
        isAvailable: @escaping (Room) -> Bool = { $0.isAvailable },
        unavailableHelp: @escaping (Room) -> String = { "\($0.subtitle) — not built yet" },
        badge: @escaping (Room) -> Int = { _ in 0 },
        @ViewBuilder footer: () -> Footer
    ) {
        self.rooms = rooms
        self.tag = tag
        self.isAvailable = isAvailable
        self.unavailableHelp = unavailableHelp
        self.badge = badge
        self.footer = footer()
    }

    public var body: some View {
        Section("Workspace") {
            ForEach(rooms) { room in
                let available = isAvailable(room)
                row(room, available: available)
                    .tag(tag(room))
                    .disabled(!available)
                    .selectionDisabled(!available)
            }
            footer
        }
    }

    /// A room's label. One that is unavailable is drawn in the tertiary style, so it reads as unavailable in every
    /// state (`.disabled` alone left it as bright as a built room on macTEM's 2026-10-13 drive). Applied only to
    /// the unavailable rows: an available row keeps the list style's own icon and text colours.
    @ViewBuilder
    private func row(_ room: Room, available: Bool) -> some View {
        let label = Label(room.title, systemImage: room.symbolName)
        Group {
            if available {
                label
            } else {
                label.foregroundStyle(.tertiary)
            }
        }
        .badge(badge(room))
        .help(available ? room.subtitle : unavailableHelp(room))
        .accessibilityLabel(room.title)
        .accessibilityIdentifier("workspace.\(room.id)")
        .accessibilityHint(available ? room.subtitle : "Not available")
    }
}

extension WorkspaceRoomsSection where Footer == EmptyView {
    public init(
        rooms: [Room],
        tag: @escaping (Room) -> Selection,
        isAvailable: @escaping (Room) -> Bool = { $0.isAvailable },
        unavailableHelp: @escaping (Room) -> String = { "\($0.subtitle) — not built yet" },
        badge: @escaping (Room) -> Int = { _ in 0 }
    ) {
        self.init(rooms: rooms, tag: tag, isAvailable: isAvailable, unavailableHelp: unavailableHelp, badge: badge) {
            EmptyView()
        }
    }
}
