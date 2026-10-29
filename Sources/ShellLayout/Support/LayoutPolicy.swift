import Foundation
import ShellControls
import SwiftUI

/// UI's whole number budget, in one file.
///
/// The rule UI is built on: **SwiftUI decides size, we decide bounds.** A
/// control is as wide as its content, a column is as wide as the user dragged
/// it, and spare space is margin. The only numbers here are the ones a
/// container genuinely cannot infer — a split column's range, a scientific
/// image's floor, and the width of a field holding six digits. Nothing in
/// UI may declare a `.frame(width:)`/`minWidth:` outside these constants;
/// the science panes are the one exception, and they take their floor from
/// `imagePaneMinimum` (or an app-side constant extending this enum) rather than spelling a number.
public nonisolated enum LayoutPolicy {
    /// Derived, not chosen: the ideal navigator plus the ideal inspector,
    /// each with its own split divider, plus two science panes at their
    /// floor with the divider between them (`sidebarWidth.ideal +
    /// inspectorWidth.ideal + 2 * splitColumnDividerAllowance +
    /// scienceMinimum` = 230 + 320 + 4 + 361 = 915). Below this the native
    /// `navigationSplitViewColumnWidth` / `inspectorColumnWidth` min/ideal/max
    /// declared in `ContentView` and the science panes fight over space the
    /// window never had — the defect the hand-rolled `WindowAnatomyPolicy`
    /// used to paper over by hiding a panel (retired 2026-09-22; its
    /// `scienceMinimum` moved here). A window this wide never needs that
    /// collapse, so the panels now track intent alone.
    public static let datasetWindowMinimumSize = CGSize(
        width: sidebarWidth.ideal + inspectorWidth.ideal + splitColumnDividerAllowance * 2 + scienceMinimum,
        height: 640
    )
    public static let datasetWindowIdealSize = CGSize(width: 1280, height: 800)

    /// The navigation column. Narrow on purpose: it holds five words and a
    /// task list, never a control. The maximum is what still fits at the
    /// window's minimum beside the inspector's minimum and both science panes
    /// (915 − 280 − 4 − 361 = 270): a saved 320-pt sidebar crashed every
    /// launch in the constraint loop at 915 pt.
    public static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (190, 230, 270)

    /// The inspector: the workspace's settings and the dataset/product
    /// descriptor. Wider than the sidebar because forms live here. At the
    /// window's floor `max` fits only with the sidebar aside (915 − 460 − 4 ≥
    /// `scienceMinimum`), which is why the sidebar steps aside when narrow
    /// (`navigatorFits`); a maximum that followed the window failed on screen
    /// (2026-09-30: SwiftUI does not shrink a column whose maximum drops).
    public static let inspectorWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (280, 320, 460)

    /// The width a science pane should keep before the sidebar steps aside:
    /// narrower than this, the window collapses the sidebar, as Xcode hides
    /// its navigator (owner's decision 2026-09-30). Above `imagePaneMinimum`,
    /// which is the floor, not the comfortable size.
    public static let sciencePaneComfortable: CGFloat = 240

    /// Whether the sidebar still fits beside the inspector (when shown) and
    /// two science panes at `sciencePaneComfortable`, each column at its
    /// ideal. False → the window collapses the sidebar
    /// (`PanelNavigation.sidebarCollapsedForWidth`).
    public static func navigatorFits(windowWidth: CGFloat, inspectorVisible: Bool) -> Bool {
        windowWidth >= navigatorLine(inspectorVisible: inspectorVisible)
    }

    /// The width below which the sidebar steps aside: the larger of the ideal
    /// columns beside two comfortable panes, and the WIDEST columns beside two
    /// panes at their floor — the fixed inspector maximum must fit wherever
    /// the sidebar stays (1095 pt with the inspector shown).
    public static func navigatorLine(inspectorVisible: Bool) -> CGFloat {
        let divider = splitColumnDividerAllowance
        let comfortable = sidebarWidth.ideal + divider
            + (inspectorVisible ? inspectorWidth.ideal + divider : 0)
            + sciencePaneComfortable * 2 + sciencePaneDividerWidth
        let widest = sidebarWidth.max + divider
            + (inspectorVisible ? inspectorWidth.max + divider : 0)
            + scienceMinimum
        return max(comfortable, widest)
    }

    /// Science: a diffraction or real-space pane below this stops being an
    /// image and becomes a smudge.
    public static let imagePaneMinimum: CGFloat = 180
    /// Both science panes' header row, so their images start at one height.
    public static let paneHeaderHeight: CGFloat = 26
    public static let sciencePaneDividerWidth: CGFloat = 1
    public static let splitColumnDividerAllowance: CGFloat = 2

    /// Two science panes at their floor, with the divider between them.
    /// Moved here from the retired `WindowAnatomyPolicy` (2026-09-22): it is
    /// part of the window's own width budget now, not a collapse threshold.
    public static let scienceMinimum: CGFloat = imagePaneMinimum * 2 + sciencePaneDividerWidth

    /// The status bar's elapsed-and-ETA readout slot, reserved.
    ///
    /// Nothing inside a split's hosted content may repeatedly change its own
    /// minimum size — that loop crashed the app on a real dataset, 2026-09-04
    /// (`open-items.md`, the constraint-loop entry), and a ticking string is
    /// the easiest way to do it by accident. So the line is laid out at a
    /// width that never moves and truncates inside it.
    ///
    /// **116, measured 2026-09-12, not chosen.** The widest string
    /// `OperationMetricsFormat.line` can produce is "5999:59 · ETA 5999:59"
    /// at 113.59 pt in the strip's own 10 pt `caption2` monospaced-digit font
    /// — a hundred hours in both fields. It replaces a 190 pt reservation that
    /// was sized for a throughput token no longer printed, and which spent
    /// most of its width blank: during a DATASET LOAD `activeOperationMetrics`
    /// is nil outright, so 190 pt of the strip was guaranteed empty beside a
    /// loading column that has its own spinner.
    public static let operationReadoutWidth: CGFloat = 116

    /// About six digits. A numeric field is never as wide as its row.
    public static let numericFieldWidth: CGFloat = NumericFieldMetrics.width   // one value: ShellControls owns it, this forwards

    // Bottom workspace + status strip + inspector vocabulary: the
    // inspector holds durable state, the bottom pane live state. Every
    // fixed point in that surface is named here.

    /// The header row of each process pane (Output · Lineage).
    public static let bottomTabBarHeight: CGFloat = 26

    /// The permanent status strip — the infobar. Phase 1 made this row the centre column's own divider. 34 pt is what
    /// it takes to hold the Run tab's live numbers at 12-pt text with a
    /// Stop button.
    public static let statusStripHeight: CGFloat = 34
    public static let infobarHorizontalPadding: CGFloat = 10
    public static let infobarItemSpacing: CGFloat = 12
    public static let infobarProgressSpacing: CGFloat = 8

    /// The toolbar's centre display — Xcode's activity viewer: the file,
    /// the room and the scan size when idle; the running operation, its
    /// bar and its elapsed/ETA when busy (the breadcrumb row it replaces is
    /// gone). A constant width, the `operationReadoutWidth` rule: a ticking
    /// string never reflows the toolbar. The maximum, not a fixed
    /// width: at a fixed 380 the display dropped out of a 1000-pt window
    /// and the surviving actions jumped to the room's leading edge. It now
    /// shrinks, middle-truncating, when the WINDOW narrows; a ticking string
    /// still never changes it.
    public static let toolbarDisplayWidth: CGFloat = 380
    /// The minimum of every compressible status slot (the toolbar display,
    /// the strip's run line and memory glance): a CONSTANT, so a ticking
    /// string can never move a slot's minimum — the constraint-loop rule
    /// ("nothing inside a split may change its own minimum", `open-items.md`).
    /// Without it, the minimum is the text's own and ticks with it.
    public static let compressibleSlotMinimum: CGFloat = 0
    /// 140 + 2 × `toolbarDisplayPadding` = the 160-pt minimum item. The
    /// toolbar fits items by their IDEAL width (measured 2026-09-22): a
    /// 14-pt pad dropped the demo's display at 915 pt, 10 pt keeps it; a
    /// long real file name can still drop it at the window's minimum.
    public static let toolbarDisplayMinimumWidth: CGFloat = 140
    /// Breathing room inside the display's capsule, each side.
    public static let toolbarDisplayPadding: CGFloat = 10

    /// The process area's share of the centre column the infobar's toggle
    /// (and ⌃⌘L) restores when nothing has ever been dragged — the owner's
    /// "default ideal".
    public static let processAreaIdealFraction: Double = 0.3

    /// The least an OPEN process area is ever drawn at (owner card Q6 a,
    /// 2026-10-04): the 26-pt pane header, about three list rows and the
    /// provenance line. A drag, a restored fraction or a window that shrank
    /// can no longer leave a header-only sliver. At the window's minimum
    /// height (640) the column keeps over 200 pt of canvas beside it.
    public static let processAreaMinimumHeight: CGFloat = 140

    /// A drag below this height closes the area — half the floor, so the
    /// bottom edge still hides it as it always did. The snap is live: it
    /// follows every drag sample, so the area shuts the moment a sample
    /// proposes less and comes back at the floor if the pointer returns
    /// before release.
    public static let processAreaSnapShutHeight: CGFloat = processAreaMinimumHeight / 2

    /// The engine · memory · residency glance slot in the infobar — a
    /// constant width, like the metrics slot, so a changing figure
    /// never reflows the strip. Sized to fit the engine's name
    /// ("Apple M3 Max · 1.4 GB · resident"). 250 was sized with the engine's name in front; the alignment
    /// (2026-10-22) drops the name, so the slot can shrink once the new text is measured. Not measured yet.
    public static let statusGlanceWidth: CGFloat = 250

    /// The live run's readout in the infobar — done / total · rate · elapsed
    /// · ETA — at 12-pt monospaced digits, the `operationReadoutWidth` rule.
    /// **396, measured 2026-09-22, not chosen:** the widest line
    /// `OperationMetricsFormat.runLine` produces, "9,999,999 / 9,999,999 ·
    /// 9999.9 positions/s · 5999:59 · ETA 5999:59", is 390.5 pt at the
    /// callout font's monospaced digits; `StatusBarMetricsTests` sweeps it.
    public static let runReadoutWidth: CGFloat = 396

    /// The inspector's rhythm (labels take their own width — no label column).
    public static let inspectorRowSpacing: CGFloat = 6
    /// The colour dot before a region's name in a spectroscopy room's regions table.
    public static let regionSwatchSize: CGFloat = 9
    public static let inspectorSectionSpacing: CGFloat = 12

    /// The inspector's header row — the Settings · Info segmented control in
    /// a row of its own.
    public static let inspectorHeaderVerticalPadding: CGFloat = 8
    /// The inspector's tab capsule (Xcode's inspector tab bar, with words):
    /// the inset of the segments inside the glass capsule, and a segment's
    /// vertical padding.
    public static let inspectorTabInset: CGFloat = 3
    public static let inspectorTabVerticalPadding: CGFloat = 4

    /// The editable value field beside an `AdjustmentSlider`.
    public static let adjustmentValueWidth: CGFloat = 64

    /// A control popover (the colorbar chip).
    public static let popoverWidth: CGFloat = 280

    /// Readable line length for prose on an otherwise empty workspace.
    public static let readableWidth: CGFloat = 560

    /// An inline progress bar beside its status text.
    public static let inlineProgressWidth: CGFloat = 110

    // `progressPercentWidth` (36 pt) was here and is DELETED — with the
    // label it reserved. A numeric percentage beside a progress bar
    // is the same fact drawn twice: `ProgressView` has no percentage API,
    // `NSProgressIndicator` has none, the HIG never asks for one, and this
    // app's own loading card a screen away already draws a determinate bar
    // with no numeral. The number now reaches VoiceOver on the bar's
    // `.accessibilityValue`, where it is useful and cannot wrap.
    // `operationMetricsWidth` (190 pt) is replaced by `operationReadoutWidth`
    // (116) above, re-measured after throughput left the line.

    /// The grabbable width of a thin divider, centred on the drawn line. A
    /// 1 pt zone put the drag on the focus ring (owner finding (c)); this
    /// is the same 9 pt the AppKit columns use.
    public static let dividerGrabWidth: CGFloat = 9

    /// Largest box with `aspect` (width / height) that fits inside `size`.
    /// Letterboxing is the pane's job everywhere an image is drawn: a
    /// scientific image that is stretched to its container is a wrong image.
    public static func fitted(in size: CGSize, aspect: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        return size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
    }
}

/// Pure layout math for the centre column's process area : the infobar is the column's own
/// divider, draggable anywhere along its whole width from the column's
/// bottom edge (process area hidden) to its top edge (canvas hidden) —
/// Xcode's two extremes. Free of `@State`/`@Bindable` so it is tested
/// directly: `WorkspaceView` reads `heights` every layout pass, the
/// infobar's drag gesture reads `fraction(afterDrag:)`, and its toggle
/// button reads `toggled(from:last:)`. `PanelNavigation.showProcessArea`
/// restores `lastProcessFraction` for the ⌃⌘L menu item.
public nonisolated enum ProcessAreaLayout {
    /// `fraction` is the process area's share of `available` — the centre
    /// column's height with the canvas header and the infobar already
    /// removed. 0 hides the process area entirely; 1 hides the canvas
    /// entirely; anything between is drawn at least
    /// `LayoutPolicy.processAreaMinimumHeight` tall (see `height`).
    public static func heights(fraction: Double, available: CGFloat) -> (canvas: CGFloat, process: CGFloat) {
        let usable = max(available, 0)
        let process = height(fraction: fraction, available: usable)
        return (usable - process, process)
    }

    /// The height an OPEN area is drawn at for a stored fraction: 0 stays 0,
    /// anything above it is floored at `LayoutPolicy.processAreaMinimumHeight`
    /// and capped at the column (a fraction over 1, or a column shorter than
    /// the floor, gives the area all of it — never a negative canvas). The
    /// floor is applied HERE, where a fraction is consumed, not where it is
    /// stored: a stored fraction is relative to a column height it cannot
    /// know, so a clamp at restore time would be wrong on every other window
    /// size. Every path — the drag, the toggle's and ⌃⌘L's restore of
    /// `lastProcessFraction`, the scene's saved `processFraction`, a value
    /// an older version stored — therefore draws at 140 pt or more.
    public static func height(fraction: Double, available: CGFloat) -> CGFloat {
        let usable = max(available, 0)
        let share = usable * CGFloat(fraction)
        guard share > 0 else { return 0 }
        return min(max(share, LayoutPolicy.processAreaMinimumHeight), usable)
    }

    /// The infobar's own toggle button: open → always shuts (0); shut →
    /// restores `last` (the fraction remembered from before it was last
    /// shut), or the default ideal when nothing has ever been dragged.
    public static func toggled(from fraction: Double, last: Double) -> Double {
        fraction > 0 ? 0 : (last > 0 ? last : LayoutPolicy.processAreaIdealFraction)
    }

    /// A drag on the infobar. SwiftUI's `translation` grows downward, and
    /// the process area sits BELOW the bar, so dragging down shrinks it —
    /// the delta is subtracted from the height the drag started at (the
    /// RENDERED height of `start`, so grabbing a stored sliver does not
    /// jump). Under `processAreaSnapShutHeight` the area closes (0); up to
    /// `processAreaMinimumHeight` it holds at the floor; above, it follows
    /// the pointer, capped at the column. It runs on every drag sample, so
    /// the close is live and reversible until release, and the fraction the
    /// navigation remembers (`lastProcessFraction`) is the last open value
    /// the drag passed through — the floor, when the drag closed the area.
    public static func fraction(afterDrag translation: CGFloat, available: CGFloat, from start: Double) -> Double {
        guard available > 0 else { return start }
        let proposed = height(fraction: start, available: available) - translation
        if proposed < LayoutPolicy.processAreaSnapShutHeight { return 0 }
        return Double(min(max(proposed, LayoutPolicy.processAreaMinimumHeight), available) / available)
    }
}

/// How a running operation's numbers are worded, in one place.
///
/// The status bar and the inspector's Performance rows both print elapsed,
/// throughput and ETA (owner decision: the numbers belong beside the
/// progress bar, not only one tab away). Two copies of "53 s" versus "0:53"
/// is exactly the drift this file exists to remove, so both read from here.
public nonisolated enum OperationMetricsFormat {
    /// Seconds as "53 s" below a minute, "2:35" above it.
    ///
    /// Above an hour it keeps counting minutes rather than growing an hours
    /// field: "119:59", not "1:59:59". The slot beside it is a constant, and a
    /// format that grows a field is a format whose width is not bounded by the
    /// sweep that measures it.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 60
            ? String(format: "%d:%02d", total / 60, total % 60)
            : "\(total) s"
    }

    /// A rate with the unit the app names for its operation ("patterns/s", "positions/s"). Which unit an
    /// operation walks is the app's knowledge (mac4DSTEM: the virtual detector walks patterns, everything else
    /// scan positions), so it is passed in.
    public static func throughput(_ rate: Double, unit: String) -> String {
        String(format: "%.1f %@", locale: .autoupdatingCurrent, rate, unit)
    }

    /// The Run tab's idle "Last run" line: the run's name and how long it
    /// took — worded differently for a run that was stopped than one that
    /// finished, so Cancel never reads as if the run completed. Takes a
    /// plain `Bool` so this formatter stays free of the app's operation
    /// types; the call site translates.
    public static func lastRun(_ name: String, elapsed: TimeInterval, cancelled: Bool) -> String {
        let durationText = duration(elapsed)
        return cancelled ? "\(name) — cancelled after \(durationText)" : "\(name) — \(durationText)"
    }

    /// The status bar's single line: elapsed, and an ETA once the run can
    /// estimate one. Elapsed is always real; an ETA it cannot yet estimate is
    /// absent rather than invented, because an invented ETA is a number the
    /// user will plan around.
    ///
    /// **THROUGHPUT IS NOT HERE** — this narrows an owner decision ("the
    /// numbers belong beside the progress bar, not only one tab away",
    /// `decisions.md`). Three things forced it and they are stated rather
    /// than assumed. Apple's own chrome carries no units-per-second
    /// anywhere — that is Activity Monitor's register, and the HIG asks
    /// only for "a description that provides additional context". It is
    /// the longest token in the line by far: the widest string this
    /// formatter could produce WITH it measured 180.9 pt, against 113.6
    /// without, so it alone was most of a 190 pt reservation in a strip now
    /// considered cluttered. And it is derivable at a glance from the bar
    /// and the elapsed time beside it, which the two numbers kept here are
    /// not derivable from anything.
    ///
    /// (In the apps this took `(metrics, for: operation)`; `operation` was
    /// never read, and the metrics are passed as their two plain values.)
    public static func line(elapsed: TimeInterval, eta: TimeInterval?) -> String {
        var parts = [duration(elapsed)]
        if let eta {
            parts.append("ETA " + duration(eta))
        }
        return parts.joined(separator: " · ")
    }

    /// The infobar's live run, one line (owner decision: the Run tab's
    /// numbers belong in the bar): done / total, the rate, then elapsed and
    /// ETA from `line`. A part that is not known yet is absent, never
    /// invented: `elapsed` nil means the run has no metrics yet (no rate,
    /// no times); `rate` is printed with `unit`.
    public static func runLine(
        done: Int?, total: Int?, elapsed: TimeInterval?, eta: TimeInterval?, rate: Double?, unit: String
    ) -> String {
        var parts: [String] = []
        if let done, let total {
            parts.append("\(SystemMonitor.count(done)) / \(SystemMonitor.count(total))")
        }
        if let elapsed {
            if let rate {
                parts.append(throughput(rate, unit: unit))
            }
            parts.append(line(elapsed: elapsed, eta: eta))
        }
        return parts.joined(separator: " · ")
    }

    /// The status strip's memory glance: app memory — the
    /// process's physical footprint, Activity Monitor's Memory column, not
    /// the mapped cube's clean file pages — in Finder's decimal style
    /// (1000-based, `displayByteString`), so this reads the same as the
    /// sidebar's "Resident": "1.4 GB", "612 MB". The caller passes DECIMAL
    /// megabytes (10^6 bytes; `SystemMonitor.residentMemoryMB()` returns the
    /// footprint in MiB, so it converts at the call site). This slot is
    /// fixed-width and ticks every 2 s, so it takes the raw MB figure rather
    /// than a pre-formatted string, the same shape as `duration`/`throughput`
    /// above. The engine's name does not belong in front of it (it never
    /// changes and tells nothing).
    public static func glance(residentMB: Double) -> String {
        // GB before MB, TB before GB: `>=`, not `>`, at each boundary — a
        // dataset that lands EXACTLY on 1 GB or 1 TB reads in the coarser
        // unit rather than as "1000.0 MB"/"1000.0 GB". The TB branch exists
        // because the GB-only formatter used to read a two-terabyte cube as
        // "2000.0 GB" — a number no reader parses at a glance the way "2.0
        // TB" does.
        if residentMB >= 1000 * 1000 {
            return String(format: "%.1f TB", locale: .autoupdatingCurrent, residentMB / (1000 * 1000))
        } else if residentMB >= 1000 {
            return String(format: "%.1f GB", locale: .autoupdatingCurrent, residentMB / 1000)
        } else {
            return String(format: "%.0f MB", locale: .autoupdatingCurrent, residentMB)
        }
    }

    /// The glance with whether the open dataset is held in memory or streamed — "1.4 GB · resident",
    /// "612 MB · streaming". mac4DSTEM keeps the residency word because it varies; macTEM streams nothing yet and
    /// calls `glance(residentMB:)`.
    public static func glance(residentMB: Double, residency isResident: Bool) -> String {
        "\(glance(residentMB: residentMB)) · \(isResident ? "resident" : "streaming")"
    }
}

/// Every byte quantity UI prints, through one formatter.
///
/// UI had three: two hand-rolled 1024-based ones that
/// disagreed on precision, and `ByteCountFormatter(.file)` at 1000. The same
/// float32 cube read 4.00 GB in the inspector and 4.29 GB in the export sheet
/// the user opens to decide whether to write it. Apple's own split — `.memory`
/// for RAM, `.file` for disk, both labelled "GB" — is defensible in isolation
/// and wrong here, because these numbers are read against each other across
/// surfaces. One style, and it is Finder's, because Finder is the reference
/// the user already has on screen.
public nonisolated func displayByteString(_ bytes: Int) -> String {
    bytes.formatted(.byteCount(style: .file))
}
