import AppKit
import SwiftUI

extension View {
    /// Text that changes every tick (a run clock), as one static-text element that VoiceOver and UI tests read live.
    ///
    /// AppKit, because SwiftUI cannot do this job: on macOS 27 SwiftUI keeps the accessibility LABEL of an element
    /// from its first render while its VALUE follows each update (MacEMUI#39, measured in a mac4DSTEM journey: the
    /// label read "0 s" while the screen drew 13 s and the value went 5 to 93 percent; computing the label from
    /// `Date()` did not help, a new `.id` per tick did but tore the element down each second). An AppKit element is
    /// asked for its label each time a client reads it, so it is always the text of the last tick drawn.
    ///
    /// The drawn view is hidden from accessibility and the element covers it exactly, so its frame is the text's.
    func liveAccessibilityText(label: String, value: String, identifier: String) -> some View {
        accessibilityHidden(true)
            .overlay(LiveAccessibilityText(label: label, value: value, identifier: identifier))
    }
}

/// The AppKit element behind `liveAccessibilityText`. Draws nothing and takes no clicks.
struct LiveAccessibilityText: NSViewRepresentable {
    let label: String
    let value: String
    let identifier: String

    func makeNSView(context: Context) -> LiveAccessibilityTextView {
        let view = LiveAccessibilityTextView()
        update(view)
        return view
    }

    func updateNSView(_ view: LiveAccessibilityTextView, context: Context) {
        update(view)
    }

    private func update(_ view: LiveAccessibilityTextView) {
        view.label = label
        view.value = value
        view.setAccessibilityIdentifier(identifier)
    }
}

/// A static-text accessibility element whose label and value are read from stored properties on every query.
final class LiveAccessibilityTextView: NSView {
    var label = "" {
        didSet {
            guard label != oldValue else { return }
            NSAccessibility.post(element: self, notification: .titleChanged)
        }
    }

    var value = "" {
        didSet {
            guard value != oldValue else { return }
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { label }
    override func accessibilityValue() -> Any? { value }
    // Clicks go to whatever is under the text.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
