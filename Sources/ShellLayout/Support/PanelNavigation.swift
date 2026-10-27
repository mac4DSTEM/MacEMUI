import Observation

/// A process-area pane's identity (Output, Lineage, ...). The package knows `.output`; an app registers its
/// others as `ProcessPaneID("lineage")` in its own extension. Also reachable as `PanelNavigation.ProcessPaneID`.
public nonisolated struct ProcessPaneID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// The activity log; every app has it.
    public static let output = ProcessPaneID("output")
}

/// The panel half of the navigation/selection seam :
/// which panes are visible and how tall the process area is. Pure view-state, no science.
///
/// The app keeps its own room/task state (`workspaceArea`, `analysisMode`, the recovery hook) in a class that OWNS a
/// `PanelNavigation` as `navigation.panels`, without forwarding properties — the same contract `StrainProductTests`
/// pins for `strain`. Orchestration (`selectWorkspace`, `changeMode`) stays with the app: switching tasks touches
/// result bookkeeping and recovery, which are the app's to coordinate. This type only stores the answer.
@Observable
public final class PanelNavigation {
    public typealias ProcessPaneID = ShellLayout.ProcessPaneID

    public init() {}

    /// The process area's share of the centre column: 0 hides it, 1 hides the canvas instead — the infobar's two
    /// extremes. `didSet` remembers the last NON-ZERO fraction it saw, so
    /// hiding the area never forgets the height the user dragged it to —
    /// the same shape `PaneSplit`'s `@SceneStorage` fraction protects
    /// against a reset-to-default, here against a reset-to-hidden.
    public var processFraction: Double = 0 {
        didSet {
            if processFraction > 0 { lastProcessFraction = processFraction }
        }
    }

    /// What `processFraction` restores to when the process area re-opens.
    /// `LayoutPolicy.processAreaIdealFraction` is where the owner's "default
    /// ideal" is named; it is read from there rather than repeating 0.3 here.
    public var lastProcessFraction: Double = LayoutPolicy.processAreaIdealFraction

    /// The process area's visibility, as the Bool the ⌃⌘L menu item
    /// and the navigation tests drive.
    /// Not stored: `Mirror` (the seam tests) sees stored properties
    /// only, so a computed forwarder is invisible to it by design.
    /// The setter is the toggle: shutting remembers nothing extra
    /// (`processFraction`'s own `didSet` already keeps `lastProcessFraction`
    /// current), opening restores it.
    public var showProcessArea: Bool {
        get { processFraction > 0 }
        set {
            processFraction = newValue ? lastProcessFraction : 0
            // Opening the area with no pane shown shows Output — an open,
            // empty area is not a valid state (owner decision).
            if newValue, shownProcessPanes.isEmpty { shownProcessPanes.insert(.output) }
        }
    }

    /// The process area's panes, modeled on Xcode's debug area: Output
    /// on the left, then the app's others (mac4DSTEM: Lineage) to its right, each with its own toggle at the
    /// infobar's right end. Not persisted, like the tab they replace.
    public var shownProcessPanes: Set<ProcessPaneID> = [.output]

    /// Toggling a pane: hiding the last visible pane closes the area, and
    /// showing a pane while the area is closed opens it — the buttons
    /// never leave the area open and empty, or a pane chosen but unseen.
    public func toggleProcessPane(_ id: ProcessPaneID) {
        if shownProcessPanes.contains(id) {
            shownProcessPanes.remove(id)
        } else {
            shownProcessPanes.insert(id)
        }
        if shownProcessPanes.isEmpty {
            showProcessArea = false
        } else if !showProcessArea {
            showProcessArea = true
        }
    }

    /// The user's INTENT for each side panel — what the toggles, the menu
    /// items and the scene storage read and write.
    public var showSidebarPane = true
    public var showInspectorPane = false

    /// Set by the window, never by a click: the sidebar steps aside when the
    /// window narrows past the line where the science panes would fall under
    /// `LayoutPolicy.sciencePaneComfortable`, as Xcode hides its navigator
    /// (owner's decision 2026-09-30). Cleared only by the user showing the
    /// sidebar (`toggleSidebar`) — it never returns by itself, because a
    /// returning sidebar grows the window. Never saved, so the intent above
    /// survives a relaunch.
    public var sidebarCollapsedForWidth = false

    public var sidebarIsVisible: Bool { showSidebarPane && !sidebarCollapsedForWidth }

    /// The Show/Hide Sidebar action: acts on what is on screen. Showing clears
    /// the width collapse — the user asked for the sidebar at this width.
    public func toggleSidebar() {
        if sidebarIsVisible {
            showSidebarPane = false
        } else {
            showSidebarPane = true
            sidebarCollapsedForWidth = false
        }
    }

    public var inspectorIsVisible: Bool { showInspectorPane }
}
