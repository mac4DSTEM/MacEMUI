//
//  VerticalPaneSplit.swift
//  Role: two panes one over the other with a divider the user drags: the spectroscopy rooms' maps over the spectrum, results and tabs (design
//        2026-10-22 §2.1). `PaneSplit`'s twin on the other axis: the fraction is stored per window under the caller's key (the caller makes the
//        key per document), keyboard and VoiceOver move it by `DividerNudge.step`, and neither pane is driven under its floor while there is room
//        for two. Not `VSplitView`, for the reason `PaneSplit` is not `HSplitView` (a minimum travelling between a SwiftUI-owned split and
//        hosted content).
//

import SwiftUI
import ShellControls
import ShellLayout

public struct VerticalPaneSplit<Top: View, Bottom: View>: View {
    private let top: Top
    private let bottom: Bottom
    private let resizeLabel: String
    private let topName: String
    private let minimumTop: CGFloat
    private let minimumBottom: CGFloat

    @SceneStorage private var storedFraction: Double
    @State private var fractionAtDragStart: CGFloat?

    /// - Parameters:
    ///   - storageKey: The scene-storage slot of the divider's position (the top pane's share of the height).
    ///   - defaultFraction: The top pane's share before the person moves the divider.
    ///   - resizeLabel, topName: The divider's VoiceOver label and the top pane's name in its value.
    ///   - minimumTop, minimumBottom: The floors, in points.
    public init(
        storageKey: String,
        defaultFraction: Double = 0.6,
        resizeLabel: String = "Resize the panes",
        topName: String = "Top pane",
        minimumTop: CGFloat = 160,
        minimumBottom: CGFloat = 160,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.top = top()
        self.bottom = bottom()
        self.resizeLabel = resizeLabel
        self.topName = topName
        self.minimumTop = minimumTop
        self.minimumBottom = minimumBottom
        self._storedFraction = SceneStorage(wrappedValue: defaultFraction, storageKey)
    }

    private var fraction: CGFloat {
        get { CGFloat(storedFraction) }
        nonmutating set { storedFraction = Double(newValue) }
    }

    /// The top pane's smallest and largest share of `usable` points: each pane keeps its floor, and below two floors the split halves evenly.
    public nonisolated static func bounds(usable: CGFloat, minimumTop: CGFloat, minimumBottom: CGFloat) -> (smallest: CGFloat, largest: CGFloat) {
        guard usable > minimumTop + minimumBottom else { return (0.5, 0.5) }
        return (minimumTop / usable, 1 - minimumBottom / usable)
    }

    public var body: some View {
        GeometryReader { geometry in
            let dividerHeight: CGFloat = 1
            let usable = max(geometry.size.height - dividerHeight, 1)
            let limits = Self.bounds(usable: usable, minimumTop: minimumTop, minimumBottom: minimumBottom)
            let clamped = min(max(fraction, limits.smallest), limits.largest)
            let topHeight = (usable * clamped).rounded()
            VStack(spacing: 0) {
                top.frame(height: topHeight).clipped()
                divider(usable: usable, limits: limits)
                bottom.frame(height: usable - topHeight).clipped()
            }
        }
    }

    private func divider(usable: CGFloat, limits: (smallest: CGFloat, largest: CGFloat)) -> some View {
        Divider()
            .contentShape(Rectangle().inset(by: -LayoutPolicy.dividerGrabWidth / 2))
            .pointerStyle(.rowResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = fractionAtDragStart ?? fraction
                        fractionAtDragStart = start
                        fraction = min(max(start + value.translation.height / usable, limits.smallest), limits.largest)
                    }
                    .onEnded { _ in fractionAtDragStart = nil }
            )
            .accessibilityLabel(resizeLabel)
            .accessibilityValue("\(topName) \(Int((min(max(fraction, limits.smallest), limits.largest) * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(DividerNudge.step, usable: usable, limits: limits)
                case .decrement: nudge(-DividerNudge.step, usable: usable, limits: limits)
                @unknown default: break
                }
            }
            .focusable(interactions: .activate)
            .onMoveCommand { direction in
                switch direction {
                case .down: nudge(DividerNudge.step, usable: usable, limits: limits)
                case .up: nudge(-DividerNudge.step, usable: usable, limits: limits)
                default: break
                }
            }
    }

    private func nudge(_ points: CGFloat, usable: CGFloat, limits: (smallest: CGFloat, largest: CGFloat)) {
        guard usable > 0 else { return }
        let start = min(max(fraction, limits.smallest), limits.largest)
        fraction = min(max(start + points / usable, limits.smallest), limits.largest)
    }
}
