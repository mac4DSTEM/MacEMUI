import SwiftUI

/// The room's one verb, as plain values the app builds from its own state (mac4DSTEM: `AppState`, the task and its
/// readiness; macTEM: EDX Quantify, EELS's run). The shell draws it; it never decides what the verb is.
///
/// Each room declares at most one verb. While a run is in flight the verb's place offers ONE
/// thing, the way to cancel it.
public struct PrimaryAction {
    /// The verb's label ("Compute Image", "Quantify"). Nil: this room has no verb, but a run may still be in flight
    /// and keep its Cancel (mac4DSTEM shows Cancel for any busy operation, whatever the room).
    public var title: String?
    /// False draws the plain `.glass` style, disabled. See `PrimaryActionButton` for why not a disabled prominent one.
    public var isEnabled: Bool
    /// The hover help. When the verb is disabled by an unmet requirement the app passes the requirement here, so the
    /// disabled state explains itself without a second readiness surface.
    public var help: String
    /// The VoiceOver hint: what the verb does.
    public var hint: String
    /// ⌘↩ unless the app says otherwise.
    public var keyEquivalent: KeyEquivalent
    public var modifiers: EventModifiers
    /// A run of this room is in flight (the app's `isBusy`).
    public var isRunning: Bool
    /// The running operation's name: Cancel's help and VoiceOver label.
    public var operationName: String?
    /// Cancels the run. Nil while running: the run cannot be cancelled, and a small spinner stands in.
    public var stop: (() -> Void)?
    /// Runs the verb.
    public var run: () -> Void

    public init(
        title: String?,
        isEnabled: Bool = true,
        help: String = "",
        hint: String = "",
        keyEquivalent: KeyEquivalent = .return,
        modifiers: EventModifiers = .command,
        isRunning: Bool = false,
        operationName: String? = nil,
        stop: (() -> Void)? = nil,
        run: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.help = help
        self.hint = hint
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers
        self.isRunning = isRunning
        self.operationName = operationName
        self.stop = stop
        self.run = run
    }
}

/// What the toolbar slot shows for a `PrimaryAction`. Pure.
public nonisolated enum PrimaryActionPresentation: Equatable, Sendable {
    /// Nothing: no verb and nothing running.
    case hidden
    /// The verb. `prominent` only when it can run: on macOS 27 a disabled `.borderedProminent` in the toolbar's glass
    /// still draws the accent fill, so a blocked verb read as ready (mac4DSTEM drive, 2026-09-30).
    case verb(prominent: Bool)
    /// A run is in flight and can be cancelled: the Cancel button takes the verb's place.
    case cancel
    /// A run is in flight and cannot be cancelled: a small spinner.
    case spinner

    public static func of(title: String?, isEnabled: Bool, isRunning: Bool, canStop: Bool) -> PrimaryActionPresentation {
        if isRunning { return canStop ? .cancel : .spinner }
        guard title != nil else { return .hidden }
        return .verb(prominent: isEnabled)
    }

    @MainActor
    public static func of(_ action: PrimaryAction?) -> PrimaryActionPresentation {
        guard let action else { return .hidden }
        return of(title: action.title, isEnabled: action.isEnabled, isRunning: action.isRunning, canStop: action.stop != nil)
    }
}

/// The toolbar's run button, at the head of the trailing group under the inspector where the room's parameters are
/// set: the single action the room runs, and — while it runs — the way to stop it. The run's progress is the
/// toolbar's centre display (`ToolbarRunDisplay`), not this button.
///
/// The app passes nil when the verb does not apply at all (no document, or a document still loading, so the load's own
/// progress in the centre column is never shadowed by a second bar up here).
public struct PrimaryActionButton: View {
    private let action: PrimaryAction?

    public init(_ action: PrimaryAction?) {
        self.action = action
    }

    public var body: some View {
        if let action {
            switch PrimaryActionPresentation.of(action) {
            case .hidden:
                EmptyView()
            case .verb(let prominent):
                // Liquid Glass like Xcode's (owner 2026-10-07). Disabled, it takes the plain `.glass` of its siblings.
                if prominent {
                    verb(action).buttonStyle(.glassProminent)
                } else {
                    verb(action).buttonStyle(.glass).disabled(true)
                }
            case .cancel:
                // While a run is in flight this slot offers ONE thing: the way to cancel it, labeled "Cancel".
                // `Label` with an icon and `.bordered`, matching every sibling toolbar item — a plain text button
                // read as collapsed beside them. A progress bar once shared this slot and squeezed the button until
                // its label truncated to "C…" (owner, 2026-09-04); the bar is the centre display now.
                Button(role: .cancel) {
                    action.stop?()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .help(action.operationName ?? "")
                .accessibilityLabel("Cancel \(action.operationName ?? "the running operation")")
                .accessibilityIdentifier("workspace.cancelAction")
            case .spinner:
                ProgressView()
                    .controlSize(.small)
                    .help(action.operationName ?? "")
            }
        }
    }

    private func verb(_ action: PrimaryAction) -> some View {
        Button(action.title ?? "") { action.run() }
            .keyboardShortcut(action.keyEquivalent, modifiers: action.modifiers)
            .help(action.help)
            .accessibilityHint(action.hint)
            .accessibilityIdentifier("workspace.primaryAction")
    }
}
