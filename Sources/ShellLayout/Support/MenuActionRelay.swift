//
//  MenuActionRelay.swift
//  Role: the one app-scoped hand-off from a File-menu command to a window
//        that does not exist yet. "Open Dataset…" (⌘O) and the like act on the
//        FOCUSED window's state; with no window open (the last one closed, the
//        app alive) or with Settings / the object table key, there is none, and
//        the items sat greyed out (mac4DSTEM's polish re-drive, 2026-10-02).
//        The command now asks for the action here and opens a window; the new
//        window takes the action once it appears, or at once when it was only
//        minimised (`requestCount`). Nothing here is persisted; the count is
//        observed by the window, never drawn.
//
//        The package does not know the actions: the app declares its enum and
//        uses `MenuActionRelay<ItsAction>`. Where an action meets a window's
//        state (`run(_:in:)`) is the app's.
//

import Foundation
import Observation

@Observable
public final class MenuActionRelay<Action: Equatable> {

    public init() {}

    @ObservationIgnored public private(set) var pendingAction: Action?
    /// Raised by every request: the one window watches it, so a request reaches a window that is already there but
    /// not focused (minimised), whose `.task` does not run again (mac4DSTEM's 2026-10-13 drive).
    public private(set) var requestCount = 0

    /// Asks for `action` to run in the next window that appears. A
    /// second request before one is taken replaces the first: the user's last
    /// gesture wins.
    public func request(_ action: Action) {
        pendingAction = action
        requestCount &+= 1
    }

    /// The pending action, once: the window that takes it clears it, so a
    /// second window appearing later does not repeat it.
    public func take() -> Action? {
        defer { pendingAction = nil }
        return pendingAction
    }

    /// Whether a File-menu item that needs a window is enabled. With
    /// no focused window it IS (it opens one); with one, unless that window
    /// is `blocked` (loading, an open in flight, or busy where the item says so).
    public nonisolated static func isEnabled(hasFocusedWindow: Bool, blocked: Bool) -> Bool {
        !hasFocusedWindow || !blocked
    }
}
