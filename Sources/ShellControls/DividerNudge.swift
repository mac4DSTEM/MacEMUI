//
//  DividerNudge.swift
//  Role: the arithmetic of moving a divider without a mouse: one arrow-key press, or one VoiceOver
//        increment/decrement, on the science panes' divider (`PaneSplit`) and on the status strip that is the
//        process area's divider (`StatusBar`). Both were drag-only. Pure, so a test holds
//        the clamps; the views only call it. The strip's rule (`processFraction`) sits beside `ProcessAreaLayout`
//        in ShellLayout as an extension of this enum.
//

import SwiftUI

public nonisolated enum DividerNudge {

    /// One key press or one VoiceOver step, in points: about a tenth of a narrow pane, enough to see, fine
    /// enough to place a divider in a few presses (the mouse remains the fast way).
    public static let step: CGFloat = 24

    /// The science split's new fraction after moving its divider `points` to the right (negative: left),
    /// clamped to the same floor the drag keeps (`smallest`, see `PaneSplit.body`).
    public static func paneFraction(from fraction: CGFloat, by points: CGFloat, usable: CGFloat, smallest: CGFloat) -> CGFloat {
        guard usable > 0 else { return fraction }
        let start = min(max(fraction, smallest), 1 - smallest)
        return min(max(start + points / usable, smallest), 1 - smallest)
    }
}
