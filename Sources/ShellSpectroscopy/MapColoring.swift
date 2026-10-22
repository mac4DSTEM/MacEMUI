//
//  MapColoring.swift
//  Role: how a spectroscopy room's maps are coloured (design 2026-10-22 §2.4): each map in one colour (black to the colour: the element's) or on one of the shared
//        colormaps, a per-document appearance the person changes in the Maps section, and the colour mix: selected maps added into one composite tile, each in its
//        own colour. Pixels are made here from a map's values (pure, tested); what the values are is the room's.
//

import ShellMetal
import SwiftUI

/// One map's colouring: black to a colour (the element's), or a shared colormap.
public nonisolated enum MapColoring: Equatable, Hashable, Sendable, Codable {
    case color(RegionColor)
    case colormap(ColormapKind)

    private enum CodingKeys: String, CodingKey { case color, colormap }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let color = try c.decodeIfPresent(RegionColor.self, forKey: .color) { self = .color(color) }
        else { self = .colormap(try c.decode(ColormapKind.self, forKey: .colormap)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let color): try c.encode(color, forKey: .color)
        case .colormap(let kind): try c.encode(kind, forKey: .colormap)
        }
    }

    /// The colour a colorbar and the mix use for the full-scale end.
    public var endColor: RegionColor {
        switch self {
        case .color(let c):
            return c
        case .colormap(let kind):
            let (r, g, b) = Colormaps.sampleRGB(Colormaps.lutRGBA(kind), 1)
            return RegionColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }
}

/// The maps added into one composite tile.
public nonisolated struct ColorMix: Equatable, Sendable, Codable {
    public var isOn = false
    /// The ids of the maps in the mix, in the order they were added.
    public var members: [String] = []

    public init() {}

    /// Adds `id` to the mix or takes it out.
    public mutating func toggle(_ id: String) {
        if let i = members.firstIndex(of: id) { members.remove(at: i) } else { members.append(id) }
    }

    /// The mix is shown when it is on and holds at least two maps.
    public var isShown: Bool { isOn && members.count >= 2 }
}

/// A document's map appearance: the colouring the person chose per map (by the map's id; a map with none keeps its default) and the colour mix. Codable for the
/// session; remembered per document by the room.
public nonisolated struct MapAppearance: Equatable, Sendable, Codable {
    public var colorings: [String: MapColoring] = [:]
    public var mix = ColorMix()

    public init() {}

    public func coloring(for id: String, default fallback: MapColoring) -> MapColoring { colorings[id] ?? fallback }

    /// Sets a map's colouring, or with nil returns it to its default.
    public mutating func set(_ coloring: MapColoring?, for id: String) { colorings[id] = coloring }

    public mutating func reset() { colorings = [:]; mix = ColorMix() }
}

/// A map the controls list: its id, its words and the colouring it has until the person changes it.
public struct MapColorItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var defaultColoring: MapColoring

    public init(id: String, title: String, defaultColoring: MapColoring) {
        self.id = id; self.title = title; self.defaultColoring = defaultColoring
    }
}

/// Pixels of a map, pure.
public nonisolated enum MapRaster {
    /// Row-major RGBA, opaque. A value maps to `f = v / upper` clamped to 0...1 (`upper` nil: the largest finite value; a map with no positive pixel is black): black to
    /// the colour at f for `.color`, the colormap at f for `.colormap`. With `width` a NaN pixel (a value the kit could not make) is hatched in grey stripes, not drawn as zero.
    public static func rgba(values: [Double], coloring: MapColoring, upper: Double? = nil, width: Int? = nil) -> [UInt8] {
        let top = upper ?? values.reduce(0.0) { max($0, $1.isFinite ? $1 : 0) }
        let lut: [UInt8]? = if case .colormap(let kind) = coloring { Colormaps.lutRGBA(kind) } else { nil }
        let base: RegionColor? = if case .color(let c) = coloring { c } else { nil }
        var out = [UInt8](repeating: 255, count: values.count * 4)
        for (i, v) in values.enumerated() {
            if let width, width > 0, v.isNaN {
                let g: UInt8 = ((i % width) + (i / width)) % 6 < 3 ? 120 : 40
                out[4 * i] = g; out[4 * i + 1] = g; out[4 * i + 2] = g
                continue
            }
            let f = top > 0 && v.isFinite ? min(max(v / top, 0), 1) : 0
            if let base {
                out[4 * i] = byte(base.red * f); out[4 * i + 1] = byte(base.green * f); out[4 * i + 2] = byte(base.blue * f)
            } else if let lut {
                let (r, g, b) = Colormaps.sampleRGB(lut, f)
                out[4 * i] = r; out[4 * i + 1] = g; out[4 * i + 2] = b
            }
        }
        return out
    }

    /// One map of a colour mix: its values, the colour it adds and the value that is full scale (nil: its largest).
    public struct MixLayer: Sendable {
        public var values: [Double]
        public var color: RegionColor
        public var upper: Double?
        public init(values: [Double], color: RegionColor, upper: Double? = nil) { self.values = values; self.color = color; self.upper = upper }
    }

    /// The layers added into one picture: each map's fraction of its own full scale times its colour, summed per channel and clamped (the Velox colour mix). All layers
    /// are `count` pixels; NaN counts as 0.
    public static func mix(_ layers: [MixLayer], count: Int) -> [UInt8] {
        var sum = [Double](repeating: 0, count: count * 3)
        for layer in layers where layer.values.count == count {
            let top = layer.upper ?? layer.values.reduce(0.0) { max($0, $1.isFinite ? $1 : 0) }
            guard top > 0 else { continue }
            for (i, v) in layer.values.enumerated() where v.isFinite {
                let f = min(max(v / top, 0), 1)
                sum[3 * i] += layer.color.red * f; sum[3 * i + 1] += layer.color.green * f; sum[3 * i + 2] += layer.color.blue * f
            }
        }
        var out = [UInt8](repeating: 255, count: count * 4)
        for i in 0..<count { out[4 * i] = byte(sum[3 * i]); out[4 * i + 1] = byte(sum[3 * i + 1]); out[4 * i + 2] = byte(sum[3 * i + 2]) }
        return out
    }

    private static func byte(_ unit: Double) -> UInt8 { UInt8((min(max(unit, 0), 1) * 255).rounded()) }
}

/// The Maps section's colour controls: one row per map (a colour or a colormap), and the colour mix.
public struct MapColorControls: View {
    @Binding private var appearance: MapAppearance
    private let items: [MapColorItem]
    @Environment(\.self) private var environment

    public init(appearance: Binding<MapAppearance>, items: [MapColorItem]) {
        self._appearance = appearance
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in row(item) }
            if items.count >= 2 {
                Toggle("Colour mix", isOn: $appearance.mix.isOn)
                    .toggleStyle(.switch)
                    .help("Add the chosen maps into one picture, each in its own colour")
                    .accessibilityIdentifier("maps.mix.toggle")
                if appearance.mix.isOn {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            Toggle(item.title, isOn: Binding(get: { appearance.mix.members.contains(item.id) }, set: { _ in appearance.mix.toggle(item.id) }))
                                .toggleStyle(.checkbox).controlSize(.small)
                                .accessibilityIdentifier("maps.mix.\(item.id)")
                        }
                    }
                }
            }
            if appearance != MapAppearance() {
                Button("Reset colours") { appearance.reset() }
                    .controlSize(.small)
                    .accessibilityIdentifier("maps.color.reset")
            }
        }
    }

    private func row(_ item: MapColorItem) -> some View {
        let coloring = appearance.coloring(for: item.id, default: item.defaultColoring)
        return HStack(spacing: 6) {
            Text(item.title).font(.callout)
            Spacer(minLength: 4)
            if case .color(let c) = coloring {
                ColorPicker("Colour of \(item.title)", selection: Binding(
                    get: { c.color },
                    set: { appearance.set(.color(RegionColor($0, resolvedIn: environment)), for: item.id) }), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityIdentifier("maps.color.\(item.id)")
            }
            Menu {
                Button("Colour") { appearance.set(item.defaultColoring.isColor ? item.defaultColoring : .color(RegionColor(red: 1, green: 1, blue: 1)), for: item.id) }
                Divider()
                ForEach(ColormapKind.allCases) { kind in
                    Button(kind.displayName) { appearance.set(.colormap(kind), for: item.id) }
                }
            } label: {
                Text(coloring.title).font(.caption)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Colour this map in one colour, or on a colormap")
            .accessibilityLabel("Colouring of \(item.title)")
            .accessibilityIdentifier("maps.coloring.\(item.id)")
        }
    }
}

extension MapColoring {
    var isColor: Bool { if case .color = self { true } else { false } }

    /// What the colouring menu shows: "Colour" or the colormap's name.
    var title: String {
        switch self {
        case .color: "Colour"
        case .colormap(let kind): kind.displayName
        }
    }
}
