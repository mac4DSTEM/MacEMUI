import SwiftUI

/// What the window shell needs to know about one of an app's rooms (workspaces): a name, a glyph, a one-line
/// description and a ⌘N number. Whether a room can be entered is the app's, told to `WorkspaceRoomsSection` through
/// its `isAvailable` closure. The app's enum owns everything else (its cases, its
/// tasks, what a room draws); the shell never switches over it.
///
/// `Identifiable.ID` is a `String` (the enum's `rawValue` in both apps) because it becomes the accessibility
/// identifier `workspace.<id>` that the UI journeys find a room by.
public nonisolated protocol WorkspaceRoom: Hashable, Identifiable, Sendable where ID == String {
    /// The sidebar row, the menu item and the toolbar display's room word.
    var title: String { get }
    /// An SF Symbol name.
    var symbolName: String { get }
    /// One line: the row's hover help and VoiceOver hint.
    var subtitle: String { get }
    /// ⌘1…⌘9 in list order, nil past nine. Derived by default for a `CaseIterable` room, so the menu and the list
    /// cannot disagree (macTEM's `shortcutDigit`).
    var shortcutNumber: Int? { get }
}

nonisolated extension WorkspaceRoom where Self: CaseIterable {
    public var shortcutNumber: Int? {
        guard let index = Self.allCases.firstIndex(of: self) else { return nil }
        let number = Self.allCases.distance(from: Self.allCases.startIndex, to: index) + 1
        return number <= 9 ? number : nil
    }
}
