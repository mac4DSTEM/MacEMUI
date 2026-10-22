//
//  SpectralRegions.swift
//  Role: the regions of a spectroscopy room (design 2026-10-22 §2.1): any number, any mix of rectangle, ellipse, polygon and line, each with a name, a
//        colour and a visible flag. This is the set the person edits and the lists, overlays and spectra read; the pixels a shape holds and the
//        numbers pooled from them are the kit's (the app turns a `RegionGeometry` into the kit's shape), so nothing here is numerics.
//

import SwiftUI

/// A position in the scan grid, in continuous pixel coordinates: x in [0, nx], y in [0, ny], pixel (i, j) covering [i, i+1) x [j, j+1).
public nonisolated struct RegionPoint: Equatable, Hashable, Sendable, Codable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// The outline of a region, in scan pixels. A rectangle and an ellipse share the box (the ellipse is inscribed in it).
public nonisolated enum RegionGeometry: Equatable, Sendable, Codable {
    case rectangle(x0: Double, y0: Double, x1: Double, y1: Double)
    case ellipse(x0: Double, y0: Double, x1: Double, y1: Double)
    /// Closed: the last vertex joins the first.
    case polygon([RegionPoint])
    /// An open segment; it pools no spectrum, it draws a profile.
    case line(RegionPoint, RegionPoint)

    /// "rectangle", "ellipse", "polygon", "line": the word a list row and an export use.
    public var kindName: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "ellipse"
        case .polygon: "polygon"
        case .line: "line"
        }
    }

    /// Whether the shape encloses pixels, so a spectrum can be pooled from it (a line cannot).
    public var poolsSpectrum: Bool {
        if case .line = self { false } else { true }
    }

    /// The smallest box that holds the outline, as (x0, y0, x1, y1).
    public var bounds: (x0: Double, y0: Double, x1: Double, y1: Double) {
        switch self {
        case .rectangle(let a, let b, let c, let d), .ellipse(let a, let b, let c, let d):
            return (min(a, c), min(b, d), max(a, c), max(b, d))
        case .polygon(let v):
            guard let f = v.first else { return (0, 0, 0, 0) }
            return v.reduce((f.x, f.y, f.x, f.y)) { (min($0.0, $1.x), min($0.1, $1.y), max($0.2, $1.x), max($0.3, $1.y)) }
        case .line(let a, let b):
            return (min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))
        }
    }

    /// The label anchor: the box's centre, for a line its midpoint.
    public var centre: RegionPoint {
        let b = bounds
        return RegionPoint(x: (b.x0 + b.x1) / 2, y: (b.y0 + b.y1) / 2)
    }

    /// A line's length in scan pixels; nil for the closed shapes.
    public var lineLength: Double? {
        guard case .line(let a, let b) = self else { return nil }
        return ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
    }
}

/// A colour as plain numbers (0...1), so a region keeps it in the session file and a person can pick any colour, not only the palette's.
public nonisolated struct RegionColor: Equatable, Hashable, Sendable, Codable {
    public var red: Double, green: Double, blue: Double
    public init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    /// The colour a picker hands back, to numbers (clamped to sRGB).
    public init(_ color: Color, resolvedIn environment: EnvironmentValues) {
        let r = color.resolve(in: environment)
        self.init(red: Double(min(max(r.red, 0), 1)), green: Double(min(max(r.green, 0), 1)), blue: Double(min(max(r.blue, 0), 1)))
    }
}

/// The colours new regions take in turn: the Okabe-Ito set (distinguishable under the common colour-vision deficiencies) and a grey, readable on a
/// dark or a light map.
public nonisolated enum RegionPalette {
    public static let colors: [RegionColor] = [
        RegionColor(red: 0.90, green: 0.62, blue: 0.00),   // orange
        RegionColor(red: 0.34, green: 0.71, blue: 0.91),   // sky blue
        RegionColor(red: 0.00, green: 0.62, blue: 0.45),   // bluish green
        RegionColor(red: 0.94, green: 0.89, blue: 0.26),   // yellow
        RegionColor(red: 0.84, green: 0.37, blue: 0.00),   // vermillion
        RegionColor(red: 0.80, green: 0.47, blue: 0.65),   // reddish purple
        RegionColor(red: 0.00, green: 0.45, blue: 0.70),   // blue
        RegionColor(red: 0.60, green: 0.60, blue: 0.60),   // grey
    ]

    /// The colour of the `index`-th region ever made, cycling.
    public static func color(at index: Int) -> RegionColor { colors[((index % colors.count) + colors.count) % colors.count] }
}

public nonisolated struct SpectralRegion: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var color: RegionColor
    public var isVisible: Bool
    public var geometry: RegionGeometry

    public init(id: UUID = UUID(), name: String, color: RegionColor, isVisible: Bool = true, geometry: RegionGeometry) {
        self.id = id; self.name = name; self.color = color; self.isVisible = isVisible; self.geometry = geometry
    }
}

/// The regions of one document, in the order they were drawn, with the one the room is acting on. A value: the app holds it in its observable state and
/// persists it with the session (`Codable`).
public nonisolated struct SpectralRegionSet: Equatable, Sendable, Codable {
    public private(set) var regions: [SpectralRegion] = []
    public var selectedID: UUID?
    /// How many regions were ever added: names and colours advance with it, so a deleted region's name and colour are not handed to the next.
    private var issued = 0

    public init() {}

    public var selected: SpectralRegion? { regions.first { $0.id == selectedID } }
    public var visible: [SpectralRegion] { regions.filter(\.isVisible) }
    /// The regions that pool a spectrum (everything but lines), visible or not: a hidden region is still compared when the person turns it on.
    public var spectrumRegions: [SpectralRegion] { regions.filter { $0.geometry.poolsSpectrum } }

    /// Adds a region named "Region 3" (the running count) in the next palette colour, and selects it. Returns its id.
    @discardableResult
    public mutating func add(_ geometry: RegionGeometry) -> UUID {
        issued += 1
        let kind = geometry.poolsSpectrum ? "Region" : "Line"
        let region = SpectralRegion(name: "\(kind) \(issued)", color: RegionPalette.color(at: issued - 1), geometry: geometry)
        regions.append(region)
        selectedID = region.id
        return region.id
    }

    public mutating func remove(_ id: UUID) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        regions.remove(at: index)
        if selectedID == id { selectedID = regions.indices.contains(index) ? regions[index].id : regions.last?.id }
    }

    public mutating func removeAll() { regions = []; selectedID = nil }

    /// A blank name is ignored: a region always has one.
    public mutating func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        edit(id) { $0.name = trimmed }
    }

    public mutating func setColor(_ id: UUID, _ color: RegionColor) { edit(id) { $0.color = color } }
    public mutating func setVisible(_ id: UUID, _ visible: Bool) { edit(id) { $0.isVisible = visible } }
    public mutating func setGeometry(_ id: UUID, _ geometry: RegionGeometry) { edit(id) { $0.geometry = geometry } }
    /// nil clears the selection; an id that is not in the set changes nothing.
    public mutating func select(_ id: UUID?) {
        guard let id else { selectedID = nil; return }
        if regions.contains(where: { $0.id == id }) { selectedID = id }
    }

    private mutating func edit(_ id: UUID, _ change: (inout SpectralRegion) -> Void) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        change(&regions[index])
    }
}
