// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only
// macem-mcp: the one MCP bridge to the agent door of mac4DSTEM and macTEM (`ShellAgentDoor`). A package of its own, apart from
// MacEMUI's: it is not part of either app, is not in an App Store build, and needs nothing but Foundation, so Linux CI builds and
// tests it. `swift build -c release --package-path AgentBridge` makes the one binary.
import PackageDescription

let package = Package(
    name: "macem-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macem-mcp", targets: ["macem-mcp"]),
    ],
    targets: [
        // Everything but `main`: the door's client and the MCP server, so the tests read them without a process or a port.
        .target(name: "AgentBridgeCore", path: "Sources/AgentBridgeCore"),
        .executableTarget(name: "macem-mcp", dependencies: ["AgentBridgeCore"], path: "Sources/macem-mcp"),
        .testTarget(name: "AgentBridgeTests", dependencies: ["AgentBridgeCore"], path: "Tests/AgentBridgeTests"),
    ],
    swiftLanguageModes: [.v5]
)
