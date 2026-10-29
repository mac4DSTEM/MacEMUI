// The EDX room's exports that are files of their own: the spectrum as `.msa` (FormatoKit's `MSAWriter`) and the numbers of a
// maps figure's scale bar (ImagoKit's `ScaleBarMath`). Nothing here is a number of the room's own; it packages what the room holds.
import Foundation
import FormatoCore
import FormatoMSA
import ImagoCore
import SpectroCore

public nonisolated enum EDXExports {

    /// The summed spectrum as an EMSA/MAS file: the energy axis of the file in keV, the counts as the file stores them, the beam
    /// energy when known. Bytes as `MSAWriter.encode` writes them (latin-1, `\r\n`).
    public static func msa(counts: [UInt64], axis: EnergyAxis, title: String, beamEnergyKeV: Double?, host: EDXRoomHost) throws -> Data {
        var bytes = Data(capacity: counts.count * 8)
        for c in counts { withUnsafeBytes(of: Double(c).bitPattern.littleEndian) { bytes.append(contentsOf: $0) } }
        let array = try FormatoArray(dataType: .float64, shape: [counts.count], bytes: bytes)
        var entries = [FormatoMetadataEntry(key: "General.title", value: .text(title), units: nil,
                                            provenance: FormatoProvenance(file: "", source: host.roomSource, rule: "the region's name"))]
        if let kv = beamEnergyKeV {
            entries.append(FormatoMetadataEntry(key: "Acquisition_instrument.TEM.beam_energy", value: .number(kv), units: "kV",
                                                provenance: FormatoProvenance(file: "", source: host.roomSource, rule: "the beam energy the room uses")))
        }
        let signal = FormatoSignal(title: title, signalType: "EDS_TEM",
                                   axes: [FormatoAxis(name: "Energy", size: counts.count, scale: axis.scale, offset: axis.offset, units: "keV", navigate: false)],
                                   metadata: FormatoMetadata(entries), data: array)
        return try MSAWriter.encode(signal, creator: host.appName)
    }

    /// The scale bar of a maps figure: its length as a fraction of the map's width and its label, from ImagoKit's `ScaleBarMath`
    /// on the scan's pixel size; nil when the file states none or the bar would not fit.
    public static func scaleBar(pixelSize: Double?, unit: String?, nx: Int, ny: Int) -> (fraction: Double, label: String)? {
        guard let pixelSize, pixelSize > 0, let unit, nx > 0, ny > 0 else { return nil }
        let cal = AxisCalibration(scale: pixelSize, unit: unit)
        guard let plan = ScaleBarMath.plan(x: cal, y: cal, width: nx, height: ny, unitLabel: { unit in
            // macTEM's UnitDisplay.label: a pixel spelling is "px", a length its canonical spelling, anything else as written.
            if ["px", "pix", "[pix]", "[px]", "pixel", "pixels"].contains(LengthUnit.normalized(unit)) { return "px" }
            return LengthUnit.canonicalReciprocalUnit(unit) ?? LengthUnit.canonicalRealUnit(unit) ?? unit
        }) else { return nil }
        return (plan.lengthPixels / Double(nx), plan.label)
    }
}
