import Foundation
import SwiftUI

/// The scene-storage keys of the window's panel intent, and the launch flags that force it. The strings are the ones
/// both apps already write today: a saved window keeps its panels across the move to the package. (A non-generic home,
/// because Swift has no static stored properties in generic types.)
public nonisolated enum ShellStorageKeys {
    public static let sidebarVisible = "workspace.navigatorVisible"
    public static let inspectorVisible = "workspace.inspectorVisible"
    public static let processFraction = "workspace.processFraction"
    public static let lastProcessFraction = "workspace.lastProcessFraction"
    public static let paneSplitFraction = "workspace.paneSplit.fraction"
    public static let processSplitFraction = "workspace.processSplit.fraction"
    /// `@AppStorage`, not scene storage: the inspector's tab is a preference of the user, not of one window.
    public static let inspectorTab = "inspector.tab"
}

/// Capture scaffolding, the `--demo-fixture` shape: a launch can force a panel state, so a scripted capture of the
/// hidden or shown panels does not depend on whatever state the last window left behind. The flag names are the ones
/// the UI journeys pass today (the sidebar's two keep their old "navigator" spelling).
public nonisolated enum ShellLaunchFlags {
    /// The panel states the arguments force, in the order they are applied: nil where no flag speaks.
    public struct Panels: Equatable, Sendable {
        public var inspector: Bool?
        public var sidebar: Bool?
        public var processArea: Bool?

        public init(inspector: Bool? = nil, sidebar: Bool? = nil, processArea: Bool? = nil) {
            self.inspector = inspector
            self.sidebar = sidebar
            self.processArea = processArea
        }
    }

    public static func panels(arguments: [String]) -> Panels {
        var panels = Panels()
        if arguments.contains("--inspector-hidden") { panels.inspector = false }
        if arguments.contains("--inspector-shown") { panels.inspector = true }
        if arguments.contains("--navigator-hidden") { panels.sidebar = false }
        if arguments.contains("--navigator-shown") { panels.sidebar = true }
        if arguments.contains("--process-area-open") { panels.processArea = true }
        return panels
    }
}

/// The app's window: a SwiftUI-only shell.
///
/// **The frozen rules** (). `NavigationSplitView` and the native
/// `.inspector` are the whole window structure — no `NSSplitViewController`,
/// no hosted AppKit shell, no custom pane chrome, no pane focus ring.
///
/// **The shape** is Xcode's:
///
/// - **Left** is navigation and nothing else: the rooms and their tasks, in a source list narrow enough to stay narrow.
/// - **Centre** owns the science panes, the infobar, and the process area below that draggable bar.
/// - **Right** is the inspector, in two tabs — **Settings**, every control the selected room owns, and **Info**, what
///   the document and the displayed product actually are.
///
/// The app supplies the four slots and a `PanelNavigation` it owns; this view owns the panel intent's scene storage,
/// the width line at which the sidebar steps aside, and where the toolbar is declared. Everything the window does for
/// the app's own sake (importers, sheets, alerts, observers, the open and the drop handlers) the app attaches to this
/// view with ordinary modifiers.
public struct ShellWindow<Sidebar: View, Canvas: View, Inspector: View, ToolbarItems: ToolbarContent>: View {
    private let navigation: PanelNavigation
    private let title: String
    private let onDropURLs: (([URL]) -> Bool)?
    private let sidebar: Sidebar
    private let canvas: Canvas
    private let inspector: Inspector
    private let toolbar: ToolbarItems

    @SceneStorage(ShellStorageKeys.sidebarVisible) private var savedSidebarVisible = true
    @SceneStorage(ShellStorageKeys.inspectorVisible) private var savedInspectorVisible = true
    /// The window's width, read from outside the split (never from a column's
    /// content, which is the constraint-loop shape): it decides when the
    /// sidebar steps aside (`LayoutPolicy.navigatorFits`).
    @State private var windowWidth: CGFloat = LayoutPolicy.datasetWindowIdealSize.width
    /// Whether a drag of files is over the window (outlines it); transient view state, nobody else's.
    @State private var dropTargeted = false

    /// - Parameters:
    ///   - title: The window's title, for the Window menu, Mission Control and accessibility. It is set and not drawn
    ///     (`.toolbar(removing: .title)`): the toolbar's centre display already names the file and the room.
    ///   - onDropURLs: Called with the URLs of a file drag dropped on the window; returns whether any was taken. Nil:
    ///     the window accepts no drop and draws no outline.
    ///   - sidebar: The sidebar column (a `WorkspaceSidebarFrame`).
    ///   - canvas: The centre column (a `WorkspaceColumn`).
    ///   - inspector: The inspector column (a `WorkspaceInspectorFrame`).
    ///   - toolbar: The detail column's toolbar (a `ShellToolbar`).
    public init(
        navigation: PanelNavigation,
        title: String,
        onDropURLs: (([URL]) -> Bool)? = nil,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder canvas: () -> Canvas,
        @ViewBuilder inspector: () -> Inspector,
        @ToolbarContentBuilder toolbar: () -> ToolbarItems
    ) {
        self.navigation = navigation
        self.title = title
        self.onDropURLs = onDropURLs
        self.sidebar = sidebar()
        self.canvas = canvas()
        self.inspector = inspector()
        self.toolbar = toolbar()
    }

    public var body: some View {
        // `WindowFillingLayout` reports the window's width, not the split's
        // rigid one: `.onGeometryChange` on the split itself measured 1190 pt
        // in a 915-pt window after a Show Sidebar that could not grow the
        // window, so the step-aside line below never fired (window fill).
        WindowFillingLayout { splitWindow }
        .modifier(DropOutline(onDropURLs: onDropURLs, isTargeted: $dropTargeted))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        // Steps aside when the window narrows past the line (and at a narrow
        // launch); never comes back by itself — a returning sidebar made
        // macOS grow the window (1150 -> 1420 pt, 2026-09-30 drive). The user
        // brings it back with the toggle, which clears the flag.
        .onChange(of: sidebarFits, initial: true) {
            if !sidebarFits { navigation.sidebarCollapsedForWidth = true }
        }
        .onAppear {
            navigation.showSidebarPane = savedSidebarVisible
            navigation.showInspectorPane = savedInspectorVisible
            applyPanelLaunchFlags()
        }
        .task {
            // Once more after the first layout: scene restoration can land
            // after `onAppear` and put the saved state back.
            try? await Task.sleep(for: .milliseconds(500))
            applyPanelLaunchFlags()
        }
        .onChange(of: navigation.showSidebarPane) {
            savedSidebarVisible = navigation.showSidebarPane
        }
        .onChange(of: navigation.showInspectorPane) {
            savedInspectorVisible = navigation.showInspectorPane
        }
    }

    private var splitWindow: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: LayoutPolicy.sidebarWidth.min,
                    ideal: LayoutPolicy.sidebarWidth.ideal,
                    max: LayoutPolicy.sidebarWidth.max
                )
        } detail: {
            canvas
                // Declared on the detail column, not on the split view.
                // Measured 2026-09-22 on macOS 27: with the title removed,
                // a toolbar declared on the split view laid these
                // `.primaryAction` items out at the content's LEADING edge,
                // beside the sidebar toggle, and a flexible `ToolbarSpacer`
                // (automatic or `.primaryAction` placement) did not move
                // them. Declared here they take the trailing edge — over
                // the inspector when it is open, at the window's edge when
                // it is not — and the toggle stays reachable either way.
                .toolbar { toolbar }
        }
        // `.inspector` sits on the split, off the detail view, so the column
        // runs from the toolbar to the window's bottom edge exactly the way
        // the sidebar already does.
        .inspector(isPresented: inspectorPresented) {
            inspector
                .inspectorColumnWidth(
                    min: LayoutPolicy.inspectorWidth.min,
                    ideal: LayoutPolicy.inspectorWidth.ideal,
                    // Fixed. A maximum that followed the window was tried and
                    // failed on screen (2026-09-30): SwiftUI does not shrink a
                    // column whose maximum drops below its width, and the
                    // overflow looped. What keeps 460 inside a narrow window is
                    // the sidebar stepping aside (`sidebarFits`).
                    max: LayoutPolicy.inspectorWidth.max
                )
                // The inspector's own toolbar carries its Settings · Info
                // picker and its ONE toggle (`WorkspaceInspectorFrame`): items
                // declared there stay in the toolbar, once, while the column
                // is hidden (measured 2026-09-22) — nothing here may add a
                // second toggle.
        }
        // The window keeps a title for the Window menu, Mission Control and
        // accessibility, but the toolbar does not draw it: the centre display
        // already reads "file · room · size", and drawing the title too would
        // duplicate it. Xcode's toolbar carries no title either.
        .navigationTitle(title)
        .toolbar(removing: .title)
        // Flat columns, glass on the buttons (owner, 2026-10-07): glass panes for the sidebar and inspector over a window
        // material were tried () and he preferred the flat columns with only the buttons in Liquid
        // Glass, as in Xcode — the toolbar's items are the system's glass, the bordered buttons in the columns are `.glass`.
    }

    /// What the split view shows and what a click writes are both intent
    /// (`PanelNavigation`) — nothing narrows it further.
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { navigation.inspectorIsVisible },
            set: { navigation.showInspectorPane = $0 }
        )
    }

    /// The sidebar's visibility rides on the same state as the Show/Hide
    /// Sidebar menu item (`sidebarIsVisible`), so the two can never disagree;
    /// the toolbar toggle acts through the same `toggleSidebar`.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { navigation.sidebarIsVisible ? .all : .detailOnly },
            set: {
                if ($0 != .detailOnly) != navigation.sidebarIsVisible {
                    navigation.toggleSidebar()
                }
            }
        )
    }

    /// Whether the sidebar fits beside the inspector and two comfortable
    /// science panes at this window's width (`LayoutPolicy.navigatorFits`).
    private var sidebarFits: Bool {
        LayoutPolicy.navigatorFits(windowWidth: windowWidth,
                                   inspectorVisible: navigation.inspectorIsVisible)
    }

    /// Capture scaffolding (see `onAppear`): only a launch flag writes here.
    private func applyPanelLaunchFlags() {
        let flags = ShellLaunchFlags.panels(arguments: ProcessInfo.processInfo.arguments)
        if let inspector = flags.inspector { navigation.showInspectorPane = inspector }
        if let sidebar = flags.sidebar { navigation.showSidebarPane = sidebar }
        if let processArea = flags.processArea { navigation.showProcessArea = processArea }
    }
}

/// The accent outline over the window while a file drag is over it (macTEM, shared). With
/// no handler the window is not a drop target and the modifier does nothing.
private struct DropOutline: ViewModifier {
    let onDropURLs: (([URL]) -> Bool)?
    @Binding var isTargeted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onDropURLs {
            content
                .dropDestination(for: URL.self) { urls, _ in onDropURLs(urls) } isTargeted: { isTargeted = $0 }
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        } else {
            content
        }
    }
}
