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
    public enum Segment: Equatable, Sendable {
        case title(String, help: String? = nil)
        /// An SF symbol; `label` is what VoiceOver says.
        case symbol(name: String, label: String, help: String? = nil)
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
                case .title(let title, let help):
                    control.setLabel(title, forSegment: i); control.setImage(nil, forSegment: i); control.setToolTip(help, forSegment: i)
                case .symbol(let name, let label, let help):
                    // The image's description is the segment's accessibility label.
                    control.setLabel("", forSegment: i)
                    control.setImage(NSImage(systemSymbolName: name, accessibilityDescription: label), forSegment: i)
                    control.setToolTip(help, forSegment: i)
                }
            }
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

        @objc func changed(_ sender: NSSegmentedControl) { selection.wrappedValue = sender.selectedSegment }
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
}
