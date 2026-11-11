// SPDX-License-Identifier: GPL-3.0-only
//
//  App.swift
//  Role: Which app the bridge speaks to. The bridge is one binary for both apps; the MCP client starts one copy per app
//        (`macem-mcp --app macTEM`), so each app is one server with its own tools, and an agent never confuses their windows.
//

import Foundation

public struct BridgeApp: Equatable {
    /// As the app names itself: in Settings, in the environment variables, in sentences to the agent.
    public var name: String
    /// What the app is, for the agent's first look.
    public var about: String

    /// The MCP server's name: the app's, lowercased.
    public var serverName: String { name.lowercased() }
    /// The environment variables' prefix: `MAC4DSTEM_AGENT_PORT`, `MACTEM_AGENT_TOKEN`, ...
    public var environmentPrefix: String { name.uppercased() + "_AGENT" }

    public static let mac4DSTEM = BridgeApp(name: "mac4DSTEM", about: "mac4DSTEM is a macOS app for 4D-STEM analysis.")
    public static let macTEM = BridgeApp(name: "macTEM", about: "macTEM is a macOS app for TEM and SEM images, diffraction, EBSD and spectroscopy (EDS, EELS).")
    public static let known = [mac4DSTEM, macTEM]

    /// The app `--app` names, in any letter case.
    public static func named(_ name: String) -> BridgeApp? {
        known.first { $0.name.lowercased() == name.lowercased() }
    }
}
