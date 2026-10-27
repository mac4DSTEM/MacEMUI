import SwiftUI

/// The inspector's two tabs. Persisted so the column comes back on the tab the user left it on.
enum InspectorTab: String, CaseIterable {
    case settings, info

    var title: String {
        switch self {
        case .settings: "Settings"
        case .info: "Info"
        }
    }

    /// The hover help; `infoHelp` is the app's wording of what Info shows.
    func help(infoHelp: String) -> String {
        switch self {
        case .settings: "Settings — the room's controls"
        case .info: infoHelp
        }
    }
}

/// The inspector chassis: the window's right column, in two tabs. **Settings** is every control the selected room
/// owns (mac4DSTEM: preceded by the one readiness surface in the app); **Info** is what the document and the
/// displayed product actually *are*. The app supplies both tabs' content; panels stay app-side.
///
/// Xcode's inspector anatomy (owner decision): the tabs are in the column's own first row under the toolbar,
/// centred, a hairline beneath; the toolbar over the inspector carries only its toggle. Two rejected alternatives: a
/// text picker up in the toolbar row (it "jumped to the left of the toggle") and a text picker row inside the
/// column ("ugly").
public struct WorkspaceInspectorFrame<Settings: View, Info: View>: View {
    private let navigation: PanelNavigation
    private let infoHelp: String
    private let settings: Settings
    private let info: Info

    @AppStorage(ShellStorageKeys.inspectorTab) private var tab: InspectorTab = .settings
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - navigation: Owns the inspector's visibility (the toggle writes it).
    ///   - infoHelp: The Info tab's hover help (mac4DSTEM: "Info — what the dataset and the product are"; macTEM:
    ///     "Info — what the image is").
    ///   - settings: The Settings tab's content. It brings its own scroll view (see `InspectorScrollColumn`) and its
    ///     own placeholder for "nothing open".
    ///   - info: The Info tab's content, likewise.
    public init(
        navigation: PanelNavigation,
        infoHelp: String = "Info — what the document and the product are",
        @ViewBuilder settings: () -> Settings,
        @ViewBuilder info: () -> Info
    ) {
        self.navigation = navigation
        self.infoHelp = infoHelp
        self.settings = settings()
        self.info = info()
    }

    /// Settings · Info sit in that first row as Xcode's inspector tab bar
    /// with words (owner decision): one glass capsule, the segments inside
    /// it, the current one a lighter pill, in Liquid Glass (the floor is
    /// macOS 27, so there is no pre-glass branch).
    @ViewBuilder
    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(InspectorTab.allCases, id: \.self) { candidate in
                let isCurrent = candidate == tab
                Button {
                    tab = candidate
                } label: {
                    Text(candidate.title)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LayoutPolicy.inspectorTabVerticalPadding)
                        .background {
                            if isCurrent {
                                Capsule().fill(colorScheme == .dark ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.background))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(candidate.help(infoHelp: infoHelp))
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .padding(LayoutPolicy.inspectorTabInset)
        // Plain `.glassEffect` — no manual rim, shadow or highlight layered
        // on top to fake the look: a hand-built approximation (rim, shadow,
        // top-down highlight) read as "not the real deal, made to look like
        // it" against this capsule's flat background. The system material
        // alone is simpler and more robust than approximating it.
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector tab")
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabRow
                .padding(.vertical, LayoutPolicy.inspectorHeaderVerticalPadding)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("inspector.tabPicker")
            switch tab {
            case .settings: settings
            case .info: info
            }
        }
        // Pinned to the top: with no document the tab's content is a short
        // placeholder that does not fill the column, and an unpinned stack
        // centres it — the tab bar sat mid-column at launch (owner
        // feedback).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The one inspector toggle, in the inspector's own toolbar section:
        // it stays in the toolbar, once, while the column is hidden
        // (measured 2026-09-22), so it needs no fallback and a fallback
        // doubles it.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InspectorToggleButton(navigation: navigation)
            }
        }
    }
}

/// The inspector's toggle, declared once, in the inspector's own toolbar.
/// ⌥⌘I here and in the View menu: one visible key (; it was a hidden ⌥⌘0 here and
/// ⌃⌘I there). Always enabled: it is a view command, and with no document the inspector shows its empty state.
struct InspectorToggleButton: View {
    let navigation: PanelNavigation

    var body: some View {
        Button {
            navigation.showInspectorPane.toggle()
        } label: {
            Label(navigation.inspectorIsVisible ? "Hide Inspector" : "Show Inspector",
                  systemImage: "sidebar.trailing")
        }
        .help(navigation.inspectorIsVisible ? "Hide the inspector" : "Show the inspector")
        .keyboardShortcut("i", modifiers: [.command, .option])
        .accessibilityIdentifier("toolbar.inspectorToggle")
    }
}

/// A tab's scrolling column: an optional first slot (mac4DSTEM: the Requirements and Interpretation sections, which
/// come before the room's own controls; macTEM has none), then the content, in the flat `VStack` of inspector sections
/// both tabs use. The app sets its own `inspectorScope` environment on the result (that value lives in `ShellInspector`,
/// which this module does not import).
public struct InspectorScrollColumn<Lead: View, Content: View>: View {
    private let lead: Lead
    private let content: Content

    public init(@ViewBuilder lead: () -> Lead, @ViewBuilder content: () -> Content) {
        self.lead = lead()
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutPolicy.inspectorSectionSpacing) {
                lead
                content
            }
            .padding()
        }
    }
}

extension InspectorScrollColumn where Lead == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.init(lead: { EmptyView() }, content: content)
    }
}
