//
//  EDXAgentTools.swift
//  Role: The agent door's tools for the shared EDS room (mac4DSTEM#254), written once here and registered by both apps: read the
//        room (file, picked elements, region, kept regions, window counts, the quantification table), pick elements, choose the
//        region, run Auto ID and Quantify, and stop. Each app says how a window reaches its `EDXSession` (`session`).
//
//  The tools only call what the room's own controls call (`toggle`, `setRole`, `selectRectangle`, `selectPin`, `runAutoID`,
//  `quantify`, `stop`), so an agent's run is the person's run. The numbers are SpectroKit's; the table is the room's results CSV.
//

import Foundation
import ShellAgentDoor
import ShellEDXModel
import SpectroEDX

public enum EDXAgentTools {

    /// The room's tools. `session` finds a window's EDS session (nil: the window has none).
    public static func tools(session: @escaping (AnyObject) -> EDXSession?) -> [AgentTool] {
        func room(_ call: AgentToolCall) -> Result<EDXSession, Refusal> {
            guard let state = call.window?.state, let found = session(state) else {
                return .failure(Refusal(status: 404, message: "This window has no EDS room."))
            }
            guard found.hasImage else {
                return .failure(Refusal(status: 404, message: "No spectrum image is open in the EDS room; open one first."))
            }
            return .success(found)
        }
        return [
            AgentTool(name: "get_eds", title: "EDS room",
                      summary: "What the EDS room holds: the file, the picked elements and their roles, the selected region, the kept "
                          + "regions, each line window's net counts with σ, Auto ID's suggestions, and once Quantify has run the "
                          + "results table (the room's CSV: k-factors, wt% and at% with their uncertainties) or why the fit failed.",
                      input: .window) { call in
                switch room(call) {
                case .failure(let refusal): return refusal.output
                case .success(let s): return .json(summary(of: s))
                }
            },
            AgentTool(name: "set_eds", title: "EDS room settings",
                      summary: "Picks elements and the region, as the periodic table and the map do; only what is given changes. add and "
                          + "remove take element symbols (comma-separated); fit_only and quantify set an element's role. region: whole "
                          + "(the whole map), rectangle or ellipse (x0, y0, x1, y1 in scan pixels, ends exclusive), or pin (a kept "
                          + "region, by name). Once Quantify has run, the fit follows every change. Wait until get_eds says not busy.",
                      input: .window,
                      parameters: [
                          AgentParameter("add", .text, summary: "Elements to pick, e.g. \"Fe, Ni\" (role quantify)."),
                          AgentParameter("remove", .text, summary: "Elements to take out."),
                          AgentParameter("fit_only", .text, summary: "Picked elements to fit but not quantify."),
                          AgentParameter("quantify", .text, summary: "Picked elements to quantify."),
                          AgentParameter("region", .choice(["whole", "rectangle", "ellipse", "pin"]), summary: "The region the spectrum sums."),
                          AgentParameter("x0", .integer(0...1_000_000), summary: "Region: first column."),
                          AgentParameter("y0", .integer(0...1_000_000), summary: "Region: first row."),
                          AgentParameter("x1", .integer(1...1_000_000), summary: "Region: column after the last."),
                          AgentParameter("y1", .integer(1...1_000_000), summary: "Region: row after the last."),
                          AgentParameter("pin", .text, summary: "Region pin: the kept region's name."),
                      ],
                      acts: true) { call in
                let s: EDXSession
                switch room(call) {
                case .failure(let refusal): return refusal.output
                case .success(let found): s = found
                }
                let a = call.arguments
                func symbols(_ key: String) -> [String] {
                    (a[key] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                let unknown = (symbols("add") + symbols("remove") + symbols("fit_only") + symbols("quantify"))
                    .filter { EDXElements.z(of: $0) == nil }
                guard unknown.isEmpty else {
                    return .refusal(status: 400, message: "Not element symbols: \(unknown.joined(separator: ", ")).")
                }
                // Taken out first, so "remove all, add these" in one call ends with these.
                for symbol in symbols("remove") where s.picks.contains(where: { $0.symbol == symbol }) { s.toggle(symbol) }
                for symbol in symbols("add") {
                    if let reason = EDXElements.unavailableReason(symbol: symbol) {
                        return .refusal(status: 409, message: "\(symbol): \(reason)")
                    }
                    if !s.picks.contains(where: { $0.symbol == symbol }) { s.toggle(symbol) }
                }
                for (key, role) in [("fit_only", EDXRole.fitOnly), ("quantify", .quantify)] {
                    for symbol in symbols(key) {
                        guard s.picks.contains(where: { $0.symbol == symbol }) else {
                            return .refusal(status: 409, message: "\(symbol) is not picked; add it first.")
                        }
                        s.setRole(role, of: symbol)
                    }
                }
                if let region = a["region"] {
                    if region != "whole", region != "pin", s.isSingleSpectrum {
                        return .refusal(status: 409, message: "This file is one spectrum: it has no map to draw a region on.")
                    }
                    switch region {
                    case "whole": s.selectWholeMap()
                    case "pin":
                        guard let name = a["pin"], let pin = s.pins.first(where: { $0.name == name }) else {
                            return .refusal(status: 404, message: "No kept region \(a["pin"] ?? ""); the room keeps "
                                + (s.pins.isEmpty ? "none." : s.pins.map(\.name).joined(separator: ", ") + "."))
                        }
                        s.selectPin(pin.id)
                    default:
                        guard let x0 = a["x0"].flatMap(Int.init), let y0 = a["y0"].flatMap(Int.init),
                              let x1 = a["x1"].flatMap(Int.init), let y1 = a["y1"].flatMap(Int.init), x1 > x0, y1 > y0 else {
                            return .refusal(status: 400, message: "A rectangle or ellipse needs x0 < x1 and y0 < y1.")
                        }
                        let rect = PixelRect(x0: x0, y0: y0, x1: x1, y1: y1)
                        if region == "rectangle" { s.drawRectangle(rect) } else { s.drawEllipse(rect) }
                    }
                }
                return .json(summary(of: s))
            },
            AgentTool(name: "run_eds", title: "EDS room action",
                      summary: "auto_id finds the elements in the region's spectrum (as Auto ID does), quantify fits and quantifies the "
                          + "picked elements (as Quantify does; from then on the fit follows every change), stop ends what runs. It "
                          + "answers at once; get_eds says busy until done, then holds the table.",
                      input: .window,
                      parameters: [AgentParameter("action", .choice(["auto_id", "quantify", "stop"]), summary: "What to run.",
                                                  required: true)],
                      acts: true) { call in
                let s: EDXSession
                switch room(call) {
                case .failure(let refusal): return refusal.output
                case .success(let found): s = found
                }
                switch call.arguments["action"] {
                case "auto_id":
                    guard s.runAutoID(explicit: true) != nil else {
                        if case .failed(let reason) = s.autoID { return .refusal(status: 409, message: reason) }
                        return .refusal(status: 409, message: "Auto ID cannot run now; wait until get_eds says not busy.")
                    }
                case "quantify":
                    if let blocker = s.quantifyBlocker { return .refusal(status: 409, message: blocker) }
                    guard s.quantify() != nil else { return .refusal(status: 409, message: "Quantify cannot run now.") }
                default:
                    s.stop()
                }
                return .json(["started": call.arguments["action"] ?? "", "busy": s.isBusy])
            },
        ]
    }

    struct Refusal: Error {
        let status: Int
        let message: String
        var output: AgentToolOutput { .refusal(status: status, message: message) }
    }

    /// The room as an agent reads it.
    static func summary(of s: EDXSession) -> [String: Any] {
        var out: [String: Any] = [
            "file": s.fileName,
            "single_spectrum": s.isSingleSpectrum,
            "busy": s.isBusy,
            "picks": s.picks.map { ["symbol": $0.symbol, "role": $0.role == .quantify ? "quantify" : "fit_only"] },
            "region": s.regionName,
            "region_pixels": s.regionPixels,
            "total_counts": Int(clamping: s.totalCounts),
            "kept_regions": s.pins.map(\.name),
            "windows": s.windowRows.map { row -> [String: Any] in
                var line: [String: Any] = ["symbol": row.symbol, "line": row.line, "net": finite(row.net), "sigma": finite(row.sigma)]
                if let note = row.note { line["note"] = note }
                if let failure = row.failure { line["failure"] = failure }
                return line
            },
        ]
        if let beam = s.beamEnergy { out["beam_energy_kev"] = beam }
        if let blocker = s.quantifyBlocker { out["quantify_blocker"] = blocker }
        switch s.autoID {
        case .done(let outcome):
            out["auto_id"] = ["region": outcome.region,
                              "suggestions": outcome.suggestions.map { ["symbol": $0.symbol, "reason": $0.reason] },
                              "uncorroborated": outcome.uncorroborated] as [String: Any]
        case .failed(let reason): out["auto_id"] = ["failed": reason]
        case .running: out["auto_id"] = "running"
        case .idle: break
        }
        if let csv = s.resultsCSV { out["results_csv"] = csv }
        if let failure = s.fitFailure { out["fit_failure"] = failure }
        return out
    }

    private static func finite(_ x: Double) -> Any { x.isFinite ? x : NSNull() }
}
