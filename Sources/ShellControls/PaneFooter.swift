// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/UI/PaneOverlays.swift lines 32-74 (macTEM@51c944c macTEM/UI/PaneOverlays.swift folded in: nothing; the struct is identical)
// Changes: made public with a public init. Drawing only, no app types.
// END MOVED FROM

import SwiftUI

// MARK: - Pane footer

/// The bottom overlay row of an image pane: the scale bar at the leading edge,
/// the colour legend at the trailing edge.
///
/// On a tall, narrow pane there is not enough width for both: the legend is
/// 146pt wide before its label, and the bar is quantized to ~70pt of *drawn*
/// length plus its own caption, so a collision is a property of the width of
/// the **drawn image box** — `LayoutPolicy.fitted(in:aspect:)`, which this
/// overlay sits inside — and NOT of the pane. For a square pattern in a pane
/// taller than it is wide the two coincide; for a rotated tall-narrow scan
/// the box stays narrow at any divider position, so that pane is stacked
/// always and correctly.
///
/// `ViewThatFits` picks side-by-side while both ideal widths fit and stacks
/// them otherwise, which keeps the wide case pixel-identical to what shipped
/// and makes the narrow case legible instead of overlapping.
public struct PaneFooter<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                leading
                Spacer(minLength: 8)
                trailing
            }
            // Legend above bar: the legend is the taller, fixed-width block, so
            // stacking it on top keeps the bar against the pane's bottom-left
            // corner where it sits in the wide case.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) { Spacer(minLength: 0); trailing }
                leading
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
