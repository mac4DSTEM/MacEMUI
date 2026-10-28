import Foundation
import SwiftUI

/// The window toolbar, Xcode's arrangement: the activity display in the
/// centre, never a button (the 2026-09-04 "C…" trap); at the trailing edge the room's verb, a fixed gap, the utility
/// icons, then the document menu; the inspector's own toggle comes after, from `WorkspaceInspectorFrame`. Always
/// there, so the analysis runs with both side panels hidden and the data at full size.
///
/// Declare it on the detail column (`ShellWindow` does).
public struct ShellToolbar<Display: View, Verb: View, Utility: ToolbarContent, DocumentMenu: View>: ToolbarContent {
    private let display: Display
    private let verb: Verb
    private let utility: Utility
    private let documentMenu: DocumentMenu

    /// - Parameters:
    ///   - display: The centre (`ToolbarRunDisplay`).
    ///   - verb: The room's one verb (`PrimaryActionButton`); Stop takes its place while a run is in flight.
    ///   - utility: The utility icons, each its own toolbar item so each overflows on its own when the window
    ///     narrows; the app gives each `.primaryAction` placement and `.visibilityPriority(.low)` (mac4DSTEM: Save to
    ///     Session, Reveal in Finder; macTEM: none today).
    ///   - documentMenu: The one menu: mac4DSTEM's Dataset, macTEM's open files and Open.
    public init(
        @ViewBuilder display: () -> Display,
        @ViewBuilder verb: () -> Verb,
        @ToolbarContentBuilder utility: () -> Utility,
        @ViewBuilder documentMenu: () -> DocumentMenu
    ) {
        self.display = display()
        self.verb = verb()
        self.utility = utility()
        self.documentMenu = documentMenu()
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            display
        }
        // The flexible spacer alone did NOT hold these items at the trailing
        // edge once the title was removed (two captures, 2026-09-22, with
        // `.automatic` and `.primaryAction` placement); declaring the toolbar
        // on the detail column did (see `ShellWindow`). The spacer stays as
        // the new toolbar model's own separator between the centre display
        // and this group.
        ToolbarSpacer(.flexible, placement: .primaryAction)
        // The room's verb heads the trailing group, beside the actions on
        // its result and under the inspector where its parameters are set
        // (parameters of the current workspace live on the
        // right). `visibilityPriority` says what overflows first when the
        // window narrows: the verb and the document menu stay, the utility
        // icons go into the overflow menu.
        ToolbarItem(placement: .primaryAction) {
            verb
        }
        .highVisibilityPriority()
        // The text-labelled verb sat flush against the icon buttons beside it; a fixed gap sets it apart as the
        // room's one verb (HIG, Toolbars: group items by function).
        ToolbarSpacer(.fixed, placement: .primaryAction)
        utility
        ToolbarItem(placement: .primaryAction) {
            documentMenu
        }
        .highVisibilityPriority()
        // No inspector toggle here: it is the inspector's own (`WorkspaceInspectorFrame`).
    }
}

extension ToolbarItem {
    /// `visibilityPriority(.high)` where the SDK has it. It is in Xcode 27's SwiftUI (Swift 6.4) only; Xcode 26.6
    /// (Swift 6.3, the macos-26 runner the apps' CI uses) has no such member, so both call sites go through here.
    /// Delete the guard once every CI builds with Xcode 27.
    func highVisibilityPriority() -> some ToolbarContent {
        #if compiler(>=6.4)
        visibilityPriority(.high)
        #else
        self
        #endif
    }
}

/// The utility slot of an app with no utility icons yet (macTEM). Draws nothing and takes no toolbar space.
public struct NoToolbarItems: ToolbarContent {
    public init() {}

    private var never: Bool { false }

    public var body: some ToolbarContent {
        if never {
            ToolbarItem(placement: .primaryAction) { EmptyView() }
        }
    }
}

extension ShellToolbar where Utility == NoToolbarItems {
    public init(@ViewBuilder display: () -> Display, @ViewBuilder verb: () -> Verb, @ViewBuilder documentMenu: () -> DocumentMenu) {
        self.display = display()
        self.verb = verb()
        self.utility = NoToolbarItems()
        self.documentMenu = documentMenu()
    }
}

/// What the toolbar's centre shows, as plain values the app builds from its own state.
public enum ToolbarDisplayState {
    /// The document, the room, and one more fact, on one line, middle-truncating. `detail` is ready text ("144
    /// positions", "256 × 256 px"): how a size is worded belongs to the app's document, not the shell. `help` is the
    /// full path, shown on hover.
    case idle(file: String, room: String, detail: String, help: String?)
    /// A run is in flight: its name, and the clock. `metrics` is asked once a second with the current date (the
    /// display ticks itself) and answers the elapsed time and, once the run can estimate one, the ETA; nil before
    /// the run has measured anything. The bar, the counts, the rate and Stop are the infobar's — one progress bar on
    /// screen, never two (mac4DSTEM 010) — so a determinate `progress` only reaches VoiceOver, as the value.
    case busy(operation: String, progress: Double?, metrics: (Date) -> (elapsed: TimeInterval, eta: TimeInterval?)?)
}

/// How the toolbar's display is worded, in one place, tested.
public nonisolated enum ToolbarDisplayFormat {
    /// "Demo.h5 · Prepare · 144 positions" — the file first (it is the
    /// window's subject), the room, then the size.
    public static func idle(file: String, room: String, detail: String) -> String {
        "\(file) · \(room) · \(detail)"
    }

    /// The running line: the operation, then elapsed (and ETA once known), "Virtual detector · 0:53". An ETA the run
    /// cannot yet estimate is absent, never invented.
    public static func busy(operation: String, elapsed: TimeInterval?, eta: TimeInterval?) -> String {
        guard let elapsed else { return operation }
        return operation + " · " + OperationMetricsFormat.line(elapsed: elapsed, eta: eta)
    }
}

/// The toolbar's centre — Xcode's activity viewer (the document's
/// name and the current process belong in the toolbar).
/// Idle: the file, the room and one fact (the size), one line, middle-truncating.
/// Busy: the running operation and its elapsed time (and ETA when the app supplies one), ticking once a
/// second. A display, never a button, in a bounded width
/// (`LayoutPolicy.toolbarDisplayWidth`) so a ticking string never reflows the
/// toolbar. The app passes nil when there is no document, or while it is still loading, like every room action.
public struct ToolbarRunDisplay: View {
    private let state: ToolbarDisplayState?

    public init(_ state: ToolbarDisplayState?) {
        self.state = state
    }

    public var body: some View {
        if let state {
            Group {
                switch state {
                case let .idle(file, room, detail, help):
                    Text(ToolbarDisplayFormat.idle(file: file, room: room, detail: detail))
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(help ?? "")
                        .accessibilityIdentifier("toolbar.display.idle")
                case let .busy(operation, progress, metrics):
                    busy(operation: operation, progress: progress, metrics: metrics)
                }
            }
            // No constant ideal: at a constant 380 the toolbar dropped the
            // display below ~1000 pt and the actions jumped leading
            // (measured 2026-09-22). The toolbar is not split content, so
            // the constraint-loop rule does not bind here; the busy line's
            // monospaced digits change its width only when a digit is added.
            .frame(minWidth: LayoutPolicy.toolbarDisplayMinimumWidth,
                   maxWidth: LayoutPolicy.toolbarDisplayWidth)
            // Outside the frame, so the system's capsule gets room around
            // the text rather than hugging it (owner decision, on a real
            // cube).
            .padding(.horizontal, LayoutPolicy.toolbarDisplayPadding)
        }
    }

    private func busy(
        operation: String, progress: Double?,
        metrics: @escaping (Date) -> (elapsed: TimeInterval, eta: TimeInterval?)?
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reading = metrics(context.date)
            Text(ToolbarDisplayFormat.busy(operation: operation, elapsed: reading?.elapsed, eta: reading?.eta))
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "")
                .accessibilityIdentifier("toolbar.display.busy")
        }
    }
}
