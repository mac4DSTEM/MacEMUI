//
//  SegmentedControl.swift
//  Role: the inspector's one segmented control, always the full inspector width (control placement standard). AppKit because SwiftUI's
//        segmented `Picker` on macOS keeps its intrinsic width whatever frame it is given; `NSSegmentedControl` with
//        `.fillEqually` fills the width it is offered. Titles or SF symbols per segment, a tooltip and an accessibility label each.
//

import AppKit
import SwiftUI

/// A segmented control over `NSSegmentedControl`: `selection` is the segment's index, -1 for none.
public struct SegmentedControl: NSViewRepresentable, Equatable {
    /// One segment. A segment with a `disabledReason` is drawn dimmed, cannot be picked, and has its reason as its tooltip (after its
    /// `help`, when it has one); the control's accessibility help names the segments that are off and why.
    public nonisolated enum Segment: Equatable, Sendable {
        case title(String, help: String? = nil, disabledReason: String? = nil)
        /// An SF symbol; `label` is what VoiceOver says.
        case symbol(name: String, label: String, help: String? = nil, disabledReason: String? = nil)

        /// Why the segment cannot be picked; nil when it can.
        public var disabledReason: String? {
            switch self {
            case .title(_, _, let reason), .symbol(_, _, _, let reason): reason
            }
        }

        public var isEnabled: Bool { disabledReason == nil }

        /// The tooltip: the help, then the reason the segment is off ("Off: …").
        var toolTip: String? {
            let help: String? = switch self {
            case .title(_, let help, _), .symbol(_, _, let help, _): help
            }
            let parts = [help, disabledReason.map { "Off: \($0)" }].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
    }

    private let label: String
    private let segments: [Segment]
    private let selection: Binding<Int>

    public init(label: String, segments: [Segment], selection: Binding<Int>) {
        self.label = label; self.segments = segments; self.selection = selection
    }

    public static func == (a: SegmentedControl, b: SegmentedControl) -> Bool {
        a.label == b.label && a.segments == b.segments && a.selection.wrappedValue == b.selection.wrappedValue
    }

    public func makeCoordinator() -> Coordinator { Coordinator(selection: selection) }

    public func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    public func updateNSView(_ control: NSSegmentedControl, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = selection
        let size = Self.controlSize(context.environment.controlSize)
        let state = Coordinator.Applied(label: label, segments: segments, selected: selection.wrappedValue, size: size)
        guard state != coordinator.applied else { return }
        if coordinator.applied?.segments != segments || coordinator.applied?.size != size || coordinator.applied?.label != label {
            control.controlSize = size
            control.setAccessibilityLabel(label)
            control.segmentCount = segments.count
            for (i, segment) in segments.enumerated() {
                switch segment {
                case .title(let title, _, _):
                    control.setLabel(title, forSegment: i); control.setImage(nil, forSegment: i)
                case .symbol(let name, let label, _, _):
                    // The image's description is the segment's accessibility label.
                    control.setLabel("", forSegment: i)
                    control.setImage(NSImage(systemSymbolName: name, accessibilityDescription: label), forSegment: i)
                }
                control.setToolTip(segment.toolTip, forSegment: i)
                // A disabled segment is dimmed and takes no click (AppKit reports it as not enabled).
                control.setEnabled(segment.isEnabled, forSegment: i)
            }
            // AppKit has no per-segment help for a title segment, so the control's own help names the segments that are off and why.
            control.setAccessibilityHelp(SegmentedMapping.offHelp(segments))
        }
        // -1 clears every segment: a selection not among the items shows none.
        if control.selectedSegment != state.selected {
            if state.selected < 0 { control.selectedSegment = -1 } else { control.selectedSegment = state.selected }
        }
        coordinator.applied = state
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    nonisolated static func controlSize(_ size: ControlSize) -> NSControl.ControlSize {
        switch size {
        case .mini: .mini
        case .small: .small
        case .regular: .regular
        case .large: .large
        case .extraLarge: .extraLarge
        @unknown default: .regular
        }
    }

    public final class Coordinator: NSObject {
        struct Applied: Equatable { var label: String; var segments: [Segment]; var selected: Int; var size: NSControl.ControlSize }
        var selection: Binding<Int>
        var applied: Applied?

        init(selection: Binding<Int>) { self.selection = selection }

        /// A pick of a disabled segment (the keyboard can still reach one) puts the control back where it was and leaves the selection alone.
        @objc func changed(_ sender: NSSegmentedControl) {
            let current = selection.wrappedValue
            let next = SegmentedMapping.pick(sender.selectedSegment, among: applied?.segments ?? [], current: current)
            if next != current { selection.wrappedValue = next }
            // Show what the binding now holds: a disabled pick, or a setter that refused the value, leaves the control where it was.
            let shown = selection.wrappedValue
            if sender.selectedSegment != shown { sender.selectedSegment = shown }
        }
    }
}

/// A segmented control over any hashable value. A selection that is not among the items shows no segment selected.
public struct SegmentedPicker<T: Hashable>: View {
    private let label: String
    private let items: [(T, SegmentedControl.Segment)]
    private let selection: Binding<T>

    public init(label: String, items: [(T, SegmentedControl.Segment)], selection: Binding<T>) {
        self.label = label; self.items = items; self.selection = selection
    }

    public var body: some View {
        SegmentedControl(label: label, segments: items.map(\.1),
                         selection: Binding(get: { SegmentedMapping.index(of: selection.wrappedValue, in: items.map(\.0)) },
                                            set: { if let value = SegmentedMapping.value(at: $0, in: items.map(\.0)) { selection.wrappedValue = value } }))
            .frame(maxWidth: .infinity)
    }
}

/// The two directions between a value and its segment, pure.
nonisolated enum SegmentedMapping {
    /// The segment of `value`, -1 when it is not among `values`.
    static func index<T: Hashable>(of value: T, in values: [T]) -> Int { values.firstIndex(of: value) ?? -1 }
    /// The value of segment `index`; nil for none or out of range.
    static func value<T>(at index: Int, in values: [T]) -> T? { values.indices.contains(index) ? values[index] : nil }
    /// The control's spoken help: each segment that is off, with its reason ("MLLS off: the fit arrives later."); nil when all are on.
    static func offHelp(_ segments: [SegmentedControl.Segment]) -> String? {
        let lines = segments.compactMap { segment -> String? in
            guard let reason = segment.disabledReason else { return nil }
            let name = switch segment {
            case .title(let title, _, _): title
            case .symbol(_, let label, _, _): label
            }
            return "\(name) off: \(reason)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: ". ")
    }
    /// The selection after the person picks segment `index`: that segment, or `current` when the segment is disabled.
    static func pick(_ index: Int, among segments: [SegmentedControl.Segment], current: Int) -> Int {
        guard segments.indices.contains(index) else { return index }
        return segments[index].isEnabled ? index : current
    }
}
