import Foundation
import SwiftUI
import ShellControls

/// One pane of the process area, registered by the app: Output in both apps, Lineage in mac4DSTEM. Each gets its own
/// toggle at the infobar's right end (Xcode's debug-bar buttons).
public struct ProcessTab {
    public let id: ProcessPaneID
    public let title: String
    /// The toggle's SF Symbol ("rectangle.leadinghalf.inset.filled" for the left pane, "rectangle.trailinghalf.inset.filled" for the right).
    public let systemImage: String
    let content: () -> AnyView

    public init<Content: View>(
        id: ProcessPaneID, title: String, systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.content = { AnyView(content()) }
    }

    /// The Output pane every app registers (the activity log); it is the left pane.
    public static func output<Content: View>(@ViewBuilder content: @escaping () -> Content) -> ProcessTab {
        ProcessTab(id: .output, title: "Output", systemImage: "rectangle.leadinghalf.inset.filled", content: content)
    }
}

/// The detail column: the science, and the infobar + process area along its bottom edge
// — the room actions and the file name live in the toolbar, not here.
///
/// **There is no workspace header.** The old `ProductWorkspaceHeader`
/// repeated the sidebar row's own title and cost about 100 pt off the top of
/// both panes; the phase-1 breadcrumb row repeated it again at 34 pt.
/// Readiness has exactly one owner — the inspector's Settings tab.
///
/// **Layout, top to bottom, one `GeometryReader` over the whole column**: the
/// canvas, the infobar (`LayoutPolicy.statusStripHeight`, fixed — the
/// column's own divider, drag gesture and all), the process area.
/// `ProcessAreaLayout.heights(fraction:available:)` turns
/// `navigation.processFraction` into the canvas and process area's
/// shares of what is left after the infobar: 0 hides the process area, 1
/// hides the canvas — the owner's two extremes; an open area is never drawn
/// under `LayoutPolicy.processAreaMinimumHeight` (owner card Q6 a). The
/// process area's height depends on nothing but that fraction and the column,
/// so switching its panes can never move the bar.
public struct WorkspaceColumn<Canvas: View, Run: View, Glance: View>: View {
    private let navigation: PanelNavigation
    private let tabs: [ProcessTab]
    private let hasDocument: Bool
    private let statusText: String
    private let isRunning: Bool
    private let canvas: Canvas
    private let run: Run
    private let glance: Glance

    @SceneStorage(ShellStorageKeys.processFraction) private var savedProcessFraction = 0.0
    @SceneStorage(ShellStorageKeys.lastProcessFraction) private var savedLastProcessFraction = LayoutPolicy.processAreaIdealFraction

    /// - Parameters:
    ///   - navigation: Owns the process area's fraction and which panes are shown.
    ///   - tabs: The registered process panes, left to right.
    ///   - hasDocument: The gate. The process area, its toggles and the divider's drag work in every room that has a
    ///     document, and only then: pass `false` while nothing is open, and while the document is still loading (the
    ///     dragged fraction is NOT reset for it — reopening restores the same split).
    ///   - statusText: The infobar's status line. Events only: the app clears it when the room or the document changes
    ///    .
    ///   - isRunning: A run is in flight. It decides the run slot's width priority: the run's numbers keep their
    ///     width longest, the idle "Last run" line gives way first.
    ///   - canvas: The science. Always in the hierarchy, even at fraction 1 where its height is 0: an `if` here
    ///     tore down both Metal views every time the infobar reached the top and rebuilt them on the way back
    ///     (mac4DSTEM, 2026-09-22). `MetalImageView` already declines to draw without a drawable, so a 0-pt, clipped
    ///     canvas costs nothing and keeps the panes' state.
    ///   - run: The run readout while `isRunning` (`InfobarRunReadout`), the last run while idle (`InfobarLastRun`),
    ///     or nothing.
    ///   - glance: The standing facts (`InfobarGlance`).
    public init(
        navigation: PanelNavigation,
        tabs: [ProcessTab],
        hasDocument: Bool,
        statusText: String,
        isRunning: Bool,
        @ViewBuilder canvas: () -> Canvas,
        @ViewBuilder run: () -> Run,
        @ViewBuilder glance: () -> Glance
    ) {
        self.navigation = navigation
        self.tabs = tabs
        self.hasDocument = hasDocument
        self.statusText = statusText
        self.isRunning = isRunning
        self.canvas = canvas()
        self.run = run()
        self.glance = glance()
    }

    /// `navigation.processFraction > 0` (via `showProcessArea`) still has to be true, but a document that is absent or
    /// still loading forces the area shut regardless of the dragged fraction.
    private var showsProcessArea: Bool {
        navigation.showProcessArea && hasDocument
    }

    public var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.height - LayoutPolicy.statusStripHeight, 0)
            let effectiveFraction = showsProcessArea ? navigation.processFraction : 0
            let heights = ProcessAreaLayout.heights(fraction: effectiveFraction, available: usable)

            VStack(spacing: 0) {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: heights.canvas)
                    .clipped()

                Infobar(navigation: navigation, tabs: tabs, hasDocument: hasDocument, availableHeight: usable,
                        statusText: statusText, isRunning: isRunning, run: run, glance: glance)

                if heights.process > 0 {
                    processArea
                        .frame(height: heights.process)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            // Both saved fractions come back as stored: they are relative to a
            // column height this window may not have, so the floor is applied
            // where they are drawn (`ProcessAreaLayout.height`), which covers
            // these two restores, the toggle's and a window that shrank.
            navigation.lastProcessFraction = savedLastProcessFraction
            navigation.processFraction = savedProcessFraction
        }
        .onChange(of: navigation.processFraction) {
            savedProcessFraction = navigation.processFraction
        }
        .onChange(of: navigation.lastProcessFraction) {
            savedLastProcessFraction = navigation.lastProcessFraction
        }
    }

    // MARK: - The process area

    /// The process area beneath the science panes — Xcode's debug area:
    /// the registered panes side by side, each shown or hidden by its own button at the infobar's right end.
    /// `body` gives this view its exact height; which panes are visible only changes what fills it — nothing here can
    /// move the bar: a pane whose content doesn't fill it lets the stack recenter it and the bar moves.
    private var processArea: some View {
        panes(tabs.filter { navigation.shownProcessPanes.contains($0.id) }[...], level: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// One pane fills the area; two or more are split by draggable dividers, each with its own stored fraction (the
    /// first keeps the key the apps have always used).
    private func panes(_ shown: ArraySlice<ProcessTab>, level: Int) -> AnyView {
        guard let first = shown.first else { return AnyView(EmptyView()) }
        if shown.count == 1 { return first.content() }
        return AnyView(
            PaneSplit(
                storageKey: level == 0 ? ShellStorageKeys.processSplitFraction : "\(ShellStorageKeys.processSplitFraction).\(level)",
                resizeLabel: "Resize the \(first.title) pane",
                leadingName: "\(first.title) pane"
            ) {
                first.content()
            } trailing: {
                panes(shown.dropFirst(), level: level + 1)
            }
        )
    }
}

// MARK: - The infobar

/// The permanent status strip along the centre column's bottom edge — one
/// line, `LayoutPolicy.statusStripHeight` tall, nothing taller (
/// live operational detail lives in the process area, so this
/// strip only glances).
///
/// **Phase 1: this IS the centre column's
/// divider.** A `DragGesture` over the whole bar — every pixel of its
/// width, via `.contentShape(Rectangle())` — reads `availableHeight` (the
/// same denominator `WorkspaceColumn`'s `ProcessAreaLayout.heights` uses) and
/// writes `navigation.processFraction` through
/// `ProcessAreaLayout.fraction(afterDrag:available:from:)`, the same way
/// `PaneSplit`'s divider carries the science panes' resize. No event monitor,
/// AppKit cursor, or hosted split view is involved.
///
/// Left: the status line (events only). Then the live run while one is in flight — the
/// bar, done / total, elapsed · ETA and Stop — or the last run
/// while idle (owner decision: the Run tab's numbers belong in the bar).
/// Then the standing glance, always on. Right: buttons
/// styled after Xcode's debug bar — one per process pane and the area's own toggle
/// — `ProcessAreaLayout.toggled(from:last:)`, the
/// same pure function `PanelNavigation.showProcessArea`'s setter
/// reimplements for the ⌃⌘L menu item.
///
/// No bar of its own: a `Divider()` above and below is its whole look.
struct Infobar<Run: View, Glance: View>: View {
    let navigation: PanelNavigation
    let tabs: [ProcessTab]
    let hasDocument: Bool
    /// The column's height without the infobar: what a drag's fraction is measured against.
    let availableHeight: CGFloat
    let statusText: String
    let isRunning: Bool
    let run: Run
    let glance: Glance

    /// The fraction the current drag started from — without it the
    /// gesture's cumulative `translation` re-applies on every change event
    /// and the bar snaps to a limit after a few points of travel, the same
    /// shape `PaneSplit.fractionAtDragStart` and the old `heightAtDragStart` both guarded against.
    @State private var fractionAtDragStart: Double?

    private var processAreaToggleBinding: Binding<Bool> {
        Binding(
            get: { navigation.processFraction > 0 },
            set: { _ in
                navigation.processFraction = ProcessAreaLayout.toggled(
                    from: navigation.processFraction,
                    last: navigation.lastProcessFraction
                )
            }
        )
    }

    /// One per pane, each toggling its pane and, through
    /// `toggleProcessPane`, the area itself when it is the last pane out or
    /// the first pane in.
    private func paneBinding(_ id: ProcessPaneID) -> Binding<Bool> {
        Binding(
            get: { navigation.shownProcessPanes.contains(id) && navigation.showProcessArea },
            set: { _ in navigation.toggleProcessPane(id) }
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard hasDocument else { return }
                let start = fractionAtDragStart ?? navigation.processFraction
                if fractionAtDragStart == nil { fractionAtDragStart = start }
                navigation.processFraction = ProcessAreaLayout.fraction(
                    afterDrag: value.translation.height, available: availableHeight, from: start
                )
            }
            .onEnded { _ in fractionAtDragStart = nil }
    }

    var body: some View {
        HStack(spacing: LayoutPolicy.infobarItemSpacing) {
            // One line, truncating — the message never dictates the bar's
            // height; `.help` carries the rest of a long line.
            Text(statusText)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(statusText)
                // The message is the line that says what just happened, so it keeps its width longest after the run's
                // numbers: under compression the order is the run's numbers (1), this message (0), then
                // the "Last run" line and the standing glance (-1) give way (mac4DSTEM design review 2026-10-21: the message was
                // the part cut, "Strain ✓ 89%…", while the machine column kept its full width). `.help` carries the rest.
                // Priorities are constant per state, so nothing here changes the strip's own minimum (the constraint-loop rule).
                .layoutPriority(0)
                .accessibilityIdentifier("status.bar")

            Spacer(minLength: LayoutPolicy.infobarItemSpacing)

            // The Run tab's numbers, here (owner decision): the bar,
            // done / total, elapsed · ETA and Stop while a run is in
            // flight; the last run while idle.
            run
                .layoutPriority(isRunning ? 1 : -1)

            glance
                .layoutPriority(-1)

            if hasDocument {
                ForEach(tabs, id: \.id) { tab in
                    Toggle(isOn: paneBinding(tab.id)) {
                        Image(systemName: tab.systemImage)
                    }
                    .toggleStyle(.button)
                    .help("\(tab.title) pane")
                    .accessibilityLabel("Toggle the \(tab.title) pane")
                    .accessibilityIdentifier("status.footer.toggle\(tab.title)")
                }
                Toggle(isOn: processAreaToggleBinding) {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                }
                .toggleStyle(.button)
                .help(navigation.showProcessArea
                      ? "Hide the bottom pane" : "Show the bottom pane")
                .accessibilityLabel("Toggle bottom pane")
                .accessibilityIdentifier("status.footer.toggleLog")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.statusStripHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .modifier(ResizePointer(axis: .row))
        .simultaneousGesture(dragGesture)
        // The strip is the bottom pane's divider and was drag-only. VoiceOver gets two
        // actions, not an adjustable value: the strip holds buttons of its own that must stay reachable, and an
        // adjustable element would swallow them. Keyboard: Tab to the strip, then Up/Down. Both do what the drag
        // does, `DividerNudge.step` at a time, and only with a document, like the drag.
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Make the bottom pane taller") { nudgeProcessArea(taller: true) }
        .accessibilityAction(named: "Make the bottom pane shorter") { nudgeProcessArea(taller: false) }
        .focusable(interactions: .activate)   // a keyboard-navigation stop only; see `PaneSplit.divider` for why not a click target
        .onMoveCommand { direction in
            switch direction {
            case .up: nudgeProcessArea(taller: true)
            case .down: nudgeProcessArea(taller: false)
            default: break
            }
        }
    }

    private func nudgeProcessArea(taller: Bool) {
        guard hasDocument else { return }
        navigation.processFraction = DividerNudge.processFraction(
            from: navigation.processFraction, taller: taller,
            last: navigation.lastProcessFraction, available: availableHeight)
    }
}

/// The live run in the infobar: the bar, then done / total · rate · elapsed · ETA, then Stop — ticking once a second,
/// in a constant-width slot (`LayoutPolicy.runReadoutWidth`: a ticking string never resizes its own container — the
/// constraint-loop rule). The app words the line (`OperationMetricsFormat.runLine`) and says what Stop does.
public struct InfobarRunReadout: View {
    private let operation: String?
    private let progress: Double?
    private let line: (Date) -> String
    private let onCancel: (() -> Void)?

    /// - Parameters:
    ///   - operation: The running operation's name, the bar's and Cancel's VoiceOver label.
    ///   - progress: 0...1, or nil for an indeterminate bar.
    ///   - line: The readout text at the given date.
    ///   - onCancel: Nil: the run cannot be cancelled and no button is drawn.
    public init(operation: String?, progress: Double?, line: @escaping (Date) -> String, onCancel: (() -> Void)?) {
        self.operation = operation
        self.progress = progress
        self.line = line
        self.onCancel = onCancel
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let text = line(context.date)
            HStack(spacing: LayoutPolicy.infobarProgressSpacing) {
                ProgressView(value: progress)
                    .frame(width: LayoutPolicy.inlineProgressWidth)
                    .accessibilityLabel(operation ?? "Progress")
                    .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "")
                Text(text)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Constant minimum, ideal and maximum, like the glance:
                    // none depends on the text, so nothing ticks, yet a
                    // narrow window compresses the slot instead of the
                    // inspector covering a pane.
                    .frame(minWidth: LayoutPolicy.compressibleSlotMinimum,
                           idealWidth: LayoutPolicy.runReadoutWidth,
                           maxWidth: LayoutPolicy.runReadoutWidth, alignment: .leading)
                    // The label from the same tick as the drawn text, re-read
                    // each tick (see `ToolbarRunDisplay`).
                    .accessibilityLabel(text)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("status.footer.metrics")
                if let onCancel {
                    // "Cancel", matching the toolbar's own button: both name
                    // the same action on the same run. `.fixedSize()` +
                    // `.layoutPriority(1)`: this row's other items (the
                    // progress bar, the fixed-width metrics text) leave the
                    // button no protected space of its own, and without them
                    // it collapsed to a blank ~9pt pill with a zero-width
                    // label when the metrics text was near its own longest
                    // content.
                    Button("Cancel", role: .cancel, action: onCancel)
                        .fixedSize()
                        .layoutPriority(1)
                        .accessibilityLabel("Cancel \(operation ?? "the running operation")")
                        .accessibilityIdentifier("status.footer.stop")
                }
            }
        }
    }
}

/// The idle "Last run" line (`OperationMetricsFormat.lastRun` is its wording): secondary text that gives way first.
public struct InfobarLastRun: View {
    private let text: String

    /// `text` is the run's line without the prefix: "Detect Disks — 2:35".
    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text("Last run · " + text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityIdentifier("status.footer.lastRun")
    }
}

/// The standing facts — memory, and whether the data is resident or streamed — always on, in a fixed slot, with the
/// chip glyph the owner asked for ("some logos if it makes sense"). The app words it
/// (`OperationMetricsFormat.glance`); the text is asked every 2 s.
public struct InfobarGlance: View {
    private let text: () -> String
    private let help: String?

    public init(help: String? = nil, text: @escaping () -> String) {
        self.help = help
        self.text = text
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            Label {
                Text(text())
            } icon: {
                Image(systemName: "memorychip")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            // Constant minimum, ideal and maximum, not a fixed width: none
            // depends on the text, so a ticking value never moves the
            // strip's size (the constraint-loop rule), yet it compresses. A
            // fixed 250 pt floored the strip — and so the detail column —
            // at ~432 pt, and the inspector drew over the right science
            // pane .
            .frame(minWidth: LayoutPolicy.compressibleSlotMinimum,
                   idealWidth: LayoutPolicy.statusGlanceWidth,
                   maxWidth: LayoutPolicy.statusGlanceWidth, alignment: .trailing)
            .help(help ?? "")
            .accessibilityIdentifier("status.footer.memoryGlance")
        }
    }
}
