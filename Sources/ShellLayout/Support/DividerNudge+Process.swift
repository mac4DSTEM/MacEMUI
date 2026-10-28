// Drop into Sources/ShellLayout/Support/DividerNudge+Process.swift. `import ShellControls` for `DividerNudge.step`.

import ShellControls
import SwiftUI

extension DividerNudge {
    /// The process area's new fraction after moving the strip up (`taller`) or down. A shut area opens to where it
    /// was last open on "taller", as the infobar's toggle does, and stays shut on "shorter"; an open one follows the
    /// drag's own rule (`ProcessAreaLayout.fraction(afterDrag:)`: it is capped at the column and held at its
    /// floor) with one difference: a mouse closes it by dragging far below the floor, which a 24-pt step never does,
    /// so "shorter" at the floor closes it.
    public static func processFraction(from fraction: Double, taller: Bool, last: Double, available: CGFloat) -> Double {
        if fraction <= 0 {
            return taller ? ProcessAreaLayout.toggled(from: 0, last: last) : 0
        }
        // Half a point of slack: the floor round-trips through a fraction (140 / 800), and a double need not give 140 back exactly.
        if !taller, ProcessAreaLayout.height(fraction: fraction, available: available) <= LayoutPolicy.processAreaMinimumHeight + 0.5 {
            return 0
        }
        return ProcessAreaLayout.fraction(afterDrag: taller ? -step : step, available: available, from: fraction)
    }
}
