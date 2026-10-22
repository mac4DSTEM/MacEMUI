// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/UI/WorkspaceView.swift (`PaneSplit`, `ResizePointer`) and mac4DSTEM/UI/BottomWorkspace.swift (`PaneHeader`) (macTEM@51c944c macTEM/UI/WorkspaceView.swift folded in: `ResizePointer` (identical); macTEM has no PaneSplit, its Output pane header is `PaneHeader`'s shape written inline)
// Changes: made public; PaneSplit's VoiceOver label and the leading pane's name are parameters (they named the diffraction and real-space panes), and the pane floor a parameter defaulting to `LayoutPolicy.imagePaneMinimum`; `PaneHeader` renamed `ProcessPaneHeader`
// END MOVED FROM

import SwiftUI
import ShellControls

/// Two panes side by side with a divider the user drags (mac4DSTEM: the diffraction and real-space panes; the process
/// area's Output and Lineage; macTEM's rooms adopt it as they are touched, alignment spec §2.2).
///
/// **Why this is not `HSplitView`** (mac4DSTEM Gate D, 2026-09-04). `HSplitView` nested
/// in the `NavigationSplitView` detail is half of a launch crash: with both it
/// and the real panes present the app aborted in AppKit's update-constraints
/// guard ~6 s after launching on the demo fixture, and removing either element
/// removed the crash. Measured, one tree: HSplitView + real panes crashes (and
/// still crashes with every `.frame(minWidth:)` removed, which refuted the
/// first diagnosis); HSplitView + `Color.clear` children survives; `HStack` +
/// real panes survives.
///
/// **What is NOT established is why.** The first written explanation — that
/// `HSplitView` hosts each child in its own `NSHostingView` and loops on a
/// content-derived minimum — was refuted by mac4DSTEM's own shipping code: the
/// old window puts two real scientific panes with
/// explicit minimums inside an `HSplitView` and does not crash. The mechanism
/// that fits every observation, including that one, is the one measured
/// in-process on 2026-09-03: a minimum
/// travelling between a SwiftUI-owned split and its hosted content. The window stacks
/// three such splits — `NavigationSplitView`, `.inspector`, `HSplitView` — and
/// every surviving probe drops it to two. Two probes would separate the two
/// readings and neither has been run; they are named in mac4DSTEM's `open-items.md`.
///
/// The fix is safe under either reading, which is why it landed on an
/// unfinished explanation: a `GeometryReader` reports the proposal and never
/// consults its children, and `.frame(width:)` terminates each pane's
/// minimum, so this view propagates no minimum upward at all. It is also
/// portable — `HSplitView` is macOS-only.
public struct PaneSplit<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing
    private let resizeLabel: String
    private let leadingName: String
    private let minimumPane: CGFloat

    /// `storageKey` names the scene-storage slot the divider's position lives
    /// in, so the science split and the process area's split each remember
    /// their own fraction.
    ///
    /// - Parameters:
    ///   - resizeLabel: The divider's VoiceOver label ("Resize the diffraction and real-space panes").
    ///   - leadingName: The leading pane's name in the divider's VoiceOver value ("Diffraction pane" reads "Diffraction
    ///     pane 50 percent").
    ///   - minimumPane: Neither pane is driven below this while there is room for two of them.
    public init(
        storageKey: String = ShellStorageKeys.paneSplitFraction,
        resizeLabel: String = "Resize the panes",
        leadingName: String = "Left pane",
        minimumPane: CGFloat = LayoutPolicy.imagePaneMinimum,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
        self.resizeLabel = resizeLabel
        self.leadingName = leadingName
        self.minimumPane = minimumPane
        self._storedFraction = SceneStorage(wrappedValue: 0.5, storageKey)
    }

    /// The divider's position as a fraction of the usable width. Where a
    /// divider sits is window state, not app state, so it lives in the
    /// scene's own storage: it survives this branch being rebuilt (a load, a
    /// trip to Results) and the window being reopened, and each window keeps
    /// its own. As `@State` it reset to centre on every rebuild — the
    /// `PaneSplit` residual (c) and the first item of mac4DSTEM's UI polish list.
    @SceneStorage private var storedFraction: Double
    @State private var fractionAtDragStart: CGFloat?

    private var fraction: CGFloat {
        get { CGFloat(storedFraction) }
        nonmutating set { storedFraction = Double(newValue) }
    }

    private var dividerWidth: CGFloat { LayoutPolicy.sciencePaneDividerWidth }

    public var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - dividerWidth, 1)
            let smallest = Self.smallestFraction(minimumPane: minimumPane, usable: usable)
            let clamped = min(max(fraction, smallest), 1 - smallest)
            let leadingWidth = (usable * clamped).rounded()

            HStack(spacing: 0) {
                leading
                    .frame(width: leadingWidth)
                divider(usable: usable, smallest: smallest)
                trailing
                    .frame(width: usable - leadingWidth)
            }
        }
    }

    /// Science: neither pane is driven below the floor while
    /// there is room for two of them. The clamp lives here, on a
    /// number this view already has, rather than as a minimum the
    /// panes announce upward — announcing one is what the crash was
    /// about. Below 2 x the floor the fraction saturates at 0.5 and
    /// both panes go under it: with 300 pt of container there is no
    /// arrangement that honours a 180 pt floor twice, so the split
    /// divides what it has evenly rather than pretending otherwise.
    nonisolated static func smallestFraction(minimumPane: CGFloat, usable: CGFloat) -> CGFloat {
        min(0.5, minimumPane / usable)
    }

    private func divider(usable: CGFloat, smallest: CGFloat) -> some View {
        Divider()
            // The drawn line is 1 pt; the grab zone is the system's 9.
            .contentShape(
                Rectangle().inset(by: -LayoutPolicy.dividerGrabWidth / 2)
            )
            .modifier(ResizePointer(axis: .column))
            // `.global` for the same reason as the infobar's gesture: the
            // divider moves with the drag, and a local translation lags it.
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = fractionAtDragStart ?? fraction
                        fractionAtDragStart = start
                        fraction = min(
                            max(start + value.translation.width / usable, smallest),
                            1 - smallest
                        )
                    }
                    .onEnded { _ in fractionAtDragStart = nil }
            )
            .accessibilityLabel(resizeLabel)
            // A route without the mouse (mac4DSTEM UI audit 2026-10-14, G4): Tab to the divider, then Left/Right; and for
            // VoiceOver an adjustable value, Up/Down on the rotor's adjust. Both move it `DividerNudge.step`.
            .accessibilityValue("\(leadingName) \(Int((min(max(fraction, smallest), 1 - smallest) * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(DividerNudge.step, usable: usable, smallest: smallest)
                case .decrement: nudge(-DividerNudge.step, usable: usable, smallest: smallest)
                @unknown default: break
                }
            }
            // `.activate`: a keyboard-navigation stop only (Full Keyboard Access), never a click target, so dragging the
            // divider leaves focus on the panes and their arrow keys keep working (mac4DSTEM: stepping the scan position).
            .focusable(interactions: .activate)
            .onMoveCommand { direction in
                switch direction {
                case .right: nudge(DividerNudge.step, usable: usable, smallest: smallest)
                case .left: nudge(-DividerNudge.step, usable: usable, smallest: smallest)
                default: break
                }
            }
    }

    private func nudge(_ points: CGFloat, usable: CGFloat, smallest: CGFloat) {
        fraction = DividerNudge.paneFraction(from: fraction, by: points, usable: usable, smallest: smallest)
    }
}

/// The resize cursor over a divider. `.column` is the pane split's
/// left–right pair; `.row` is the infobar's up–down pair — the bar is
/// draggable over its whole width and needs a cursor that says so
/// (mac4DSTEM window-design §1).
struct ResizePointer: ViewModifier {
    enum Axis { case column, row }
    let axis: Axis

    func body(content: Content) -> some View {
        switch axis {
        case .column: content.pointerStyle(.columnResize)
        case .row: content.pointerStyle(.rowResize)
        }
    }
}

/// A process pane's header row: its name at the left, its one action at the right. Both apps' Output panes (and
/// mac4DSTEM's Lineage pane) put this at their top.
public struct ProcessPaneHeader<Action: View>: View {
    private let title: String
    private let action: Action

    public init(title: String, @ViewBuilder action: () -> Action) {
        self.title = title
        self.action = action()
    }

    public var body: some View {
        HStack(spacing: LayoutPolicy.inspectorRowSpacing) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            action
        }
        .controlSize(.small)
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.bottomTabBarHeight)
        .overlay(alignment: .bottom) { Divider() }
    }
}
