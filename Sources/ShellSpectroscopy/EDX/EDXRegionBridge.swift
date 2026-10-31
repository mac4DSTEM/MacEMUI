//
//  EDXRegionBridge.swift
//  Role: the EDX room's regions in MacEMUI's words. The session keeps the regions (pins) and lines; the shared Regions list, overlay and spectrum layers
//        speak `SpectralRegionSet`, `SpectrumLayer` and `ProfileSeries`. This file converts both ways and nothing else: no number is made here.
//

import SwiftUI
import ShellEDXModel
import SpectroCore
import SpectroEDX

public enum EDXRegionBridge {
    public static func geometry(_ region: EDXRegion) -> RegionGeometry? {
        switch region {
        case .wholeMap, .pool: nil
        case .rectangle(let r): .rectangle(x0: Double(r.x0), y0: Double(r.y0), x1: Double(r.x1), y1: Double(r.y1))
        case .ellipse(let r): .ellipse(x0: Double(r.x0), y0: Double(r.y0), x1: Double(r.x1), y1: Double(r.y1))
        case .polygon(let v): .polygon(v.map { RegionPoint(x: $0.x, y: $0.y) })
        }
    }

    /// A region from a geometry the drawing layer edited: boxes are whole pixels already; a line has no region (nil).
    public static func region(_ geometry: RegionGeometry) -> EDXRegion? {
        switch geometry {
        case .rectangle(let x0, let y0, let x1, let y1): .rectangle(PixelRect(x0: Int(x0.rounded()), y0: Int(y0.rounded()), x1: Int(x1.rounded()), y1: Int(y1.rounded())))
        case .ellipse(let x0, let y0, let x1, let y1): .ellipse(PixelRect(x0: Int(x0.rounded()), y0: Int(y0.rounded()), x1: Int(x1.rounded()), y1: Int(y1.rounded())))
        case .polygon(let v): .polygon(v.map { PixelPoint(x: $0.x, y: $0.y) })
        case .line: nil
        }
    }

    /// An edit of the drawing layer, as the session's call.
    public static func edit(_ id: UUID, _ geometry: RegionGeometry, in session: EDXSession) {
        if let region = region(geometry) { session.setPinRegion(id, region) }
        else if case .line(let a, let b) = geometry { session.setLineEnds(id, from: PixelPoint(x: a.x, y: a.y), to: PixelPoint(x: b.x, y: b.y)) }
    }

    public static func color(_ stored: EDXPinColor?, number: Int) -> RegionColor {
        stored.map { RegionColor(red: $0.red, green: $0.green, blue: $0.blue) } ?? RegionPalette.color(at: number - 1)
    }

    /// An element's map colour until the person changes it: its hue at full brightness, black to that colour.
    public static func defaultColoring(_ symbol: String) -> MapColoring {
        let rgb = EDXRoomFormat.rgb(hue: EDXRoomFormat.hue(symbol: symbol))
        return .color(RegionColor(red: rgb.0, green: rgb.1, blue: rgb.2))
    }

    public static func stored(_ c: RegionColor) -> EDXPinColor { EDXPinColor(red: c.red, green: c.green, blue: c.blue) }

    /// The session's pins and lines as one set. `linesFocused` says which kind the selection belongs to (the last one the person touched).
    public static func set(_ session: EDXSession, linesFocused: Bool) -> SpectralRegionSet {
        var regions: [SpectralRegion] = []
        for pin in session.pins {
            guard let g = geometry(pin.region) else { continue }
            regions.append(SpectralRegion(id: pin.id, name: pin.name, color: color(pin.color, number: pin.number), isVisible: pin.isVisible, geometry: g))
        }
        for line in session.lines {
            regions.append(SpectralRegion(id: line.id, name: line.name, color: color(line.color, number: line.number), isVisible: line.isVisible,
                                          geometry: .line(RegionPoint(x: line.from.x, y: line.from.y), RegionPoint(x: line.to.x, y: line.to.y))))
        }
        let selected = linesFocused ? session.selectedLineID : session.selectedPin?.id
        return SpectralRegionSet(regions: regions, selectedID: selected)
    }

    /// What the Regions list changed: the edits of `new` against `old` become the session's calls (rename, colour, show/hide, delete, select).
    package static func apply(_ new: SpectralRegionSet, to session: EDXSession, from old: SpectralRegionSet, state: EDXRoomState) {
        let kept = Set(new.regions.map(\.id))
        for region in old.regions where !kept.contains(region.id) {
            if session.pins.contains(where: { $0.id == region.id }) { session.removePin(region.id) } else { session.removeLine(region.id) }
        }
        for region in new.regions {
            guard let before = old.regions.first(where: { $0.id == region.id }) else { continue }
            let isPin = session.pins.contains { $0.id == region.id }
            if region.name != before.name { isPin ? session.renamePin(region.id, to: region.name) : session.renameLine(region.id, to: region.name) }
            if region.color != before.color { isPin ? session.setPinColor(region.id, stored(region.color)) : session.setLineColor(region.id, stored(region.color)) }
            if region.isVisible != before.isVisible { isPin ? session.setPinVisible(region.id, region.isVisible) : session.setLineVisible(region.id, region.isVisible) }
        }
        if new.selectedID != old.selectedID, let id = new.selectedID {
            if session.pins.contains(where: { $0.id == id }) { state.linesFocused = false; session.selectPin(id) }
            else { state.linesFocused = true; session.selectLine(id) }
        }
    }

    /// A click on a region of the colour mix selects it; a click on none returns to the whole map.
    public static func select(_ id: UUID?, in session: EDXSession, state: EDXRoomState) {
        guard let id else { state.linesFocused = false; session.selectWholeMap(); return }
        if session.pins.contains(where: { $0.id == id }) { state.linesFocused = false; session.selectPin(id) }
        else { state.linesFocused = true; session.selectLine(id) }
    }

    /// The delete key: the selected region (or line) goes; the selection falls back to the whole map.
    public static func deleteSelected(in session: EDXSession, state: EDXRoomState) {
        if state.linesFocused, let id = session.selectedLineID { session.removeLine(id); return }
        guard let pin = session.selectedPin else { return }
        session.removePin(pin.id)
        session.selectWholeMap()
    }

    // MARK: The keyboard route (a map with the focus: after a click on it, or by Tab)

    /// The shape Return draws with `tool` on a scan `nx` x `ny`: the middle half of the scan, a pixel at least (a polygon is that box's four corners, a line
    /// along the centres of its middle row). nil for the arrow tool or an empty scan.
    nonisolated static func keyboardShape(_ tool: RegionTool, nx: Int, ny: Int) -> RegionGeometry? {
        guard nx > 0, ny > 0 else { return nil }
        let w = max(nx / 2, 1), h = max(ny / 2, 1)
        let x0 = Double((nx - w) / 2), y0 = Double((ny - h) / 2), x1 = x0 + Double(w), y1 = y0 + Double(h)
        switch tool {
        case .pointer: return nil
        case .rectangle: return .rectangle(x0: x0, y0: y0, x1: x1, y1: y1)
        case .ellipse: return .ellipse(x0: x0, y0: y0, x1: x1, y1: y1)
        case .polygon: return .polygon([RegionPoint(x: x0, y: y0), RegionPoint(x: x1, y: y0), RegionPoint(x: x1, y: y1), RegionPoint(x: x0, y: y1)])
        case .line: return .line(RegionPoint(x: x0, y: Double(ny / 2) + 0.5), RegionPoint(x: x1, y: Double(ny / 2) + 0.5))
        }
    }

    /// Return: the chosen tool's shape is drawn as the mouse draws it (kept as the next numbered region, or line, and selected). False with the arrow tool
    /// or when nothing was drawn, so the key is left to whatever else wants it.
    @discardableResult
    static func drawByKeyboard(in session: EDXSession, state: EDXRoomState) -> Bool {
        guard let source = session.source, let shape = keyboardShape(state.tool, nx: source.nx, ny: source.ny) else { return false }
        switch shape {
        case .line(let a, let b):
            guard session.drawLine(from: PixelPoint(x: a.x, y: a.y), to: PixelPoint(x: b.x, y: b.y)) != nil else { return false }
            state.linesFocused = true
        case .rectangle(let x0, let y0, let x1, let y1):
            state.linesFocused = false
            session.drawRectangle(PixelRect(x0: Int(x0), y0: Int(y0), x1: Int(x1), y1: Int(y1)))
        case .ellipse(let x0, let y0, let x1, let y1):
            state.linesFocused = false
            session.drawEllipse(PixelRect(x0: Int(x0), y0: Int(y0), x1: Int(x1), y1: Int(y1)))
        case .polygon(let v):
            state.linesFocused = false
            session.drawPolygon(v.map { PixelPoint(x: $0.x, y: $0.y) })
        }
        return true
    }

    /// The step an arrow key moves the selected region, in scan pixels: one, ten with shift; nil for any other key.
    nonisolated static func arrowStep(_ key: KeyEquivalent, shift: Bool) -> (dx: Int, dy: Int)? {
        let n = shift ? 10 : 1
        switch key {
        case .leftArrow: return (-n, 0)
        case .rightArrow: return (n, 0)
        case .upArrow: return (0, -n)
        case .downArrow: return (0, n)
        default: return nil
        }
    }

    /// An arrow key: the selected region (or line) moves by `dx`, `dy` scan pixels, kept on the scan, as a drag on its body moves it. False when nothing is
    /// selected, the selection is hidden, or it cannot move further.
    @discardableResult
    static func nudgeSelected(dx: Int, dy: Int, in session: EDXSession, state: EDXRoomState) -> Bool {
        guard let source = session.source, let selected = set(session, linesFocused: state.linesFocused).selected, selected.isVisible else { return false }
        let moved = RegionEditing.moved(selected.geometry, dx: Double(dx), dy: Double(dy), scanWidth: source.nx, scanHeight: source.ny)
        guard moved != selected.geometry else { return false }
        edit(selected.id, moved, in: session)
        return true
    }

    /// One layer per visible region (in its colour, named as the list names it), plus the pointer's pixel when there is one.
    public static func layers(_ session: EDXSession, pixel: [Double]?, plot: EDXPlot) -> [SpectrumLayer] {
        var out: [SpectrumLayer] = []
        for pin in session.pins where pin.isVisible {
            guard let counts = session.pinSpectra[pin.id] else { continue }
            out.append(SpectrumLayer(id: pin.id.uuidString, name: pin.name, color: color(pin.color, number: pin.number),
                                     origin: plot.energyStart, step: plot.energyStep, counts: counts))
        }
        if let pixel {
            out.append(SpectrumLayer(id: "pixel", name: "Pixel", color: RegionColor(red: 1, green: 1, blue: 1),
                                     origin: plot.energyStart, step: plot.energyStep, counts: pixel, isTemporary: true))
        }
        return out
    }

    /// The selected line's profile, one series per element in the element's own hue.
    public static func series(_ session: EDXSession) -> [ProfileSeries] {
        session.profiles().compactMap { p in
            guard !p.samples.isEmpty else { return nil }
            // Positions are in scan pixels; with the file's pixel size they are in its unit.
            let spacing = (p.positions.count > 1 ? p.positions[1] - p.positions[0] : 1) * (session.scanPixel?.size ?? 1)
            let rgb = EDXRoomFormat.rgb(hue: EDXRoomFormat.hue(symbol: p.symbol))
            return ProfileSeries(id: p.symbol, name: p.symbol, color: RegionColor(red: rgb.0, green: rgb.1, blue: rgb.2), values: p.samples, spacing: spacing)
        }
    }
}
