// SPDX-License-Identifier: GPL-3.0-only
//
//  macem-mcp: the MCP bridge to the agent door of mac4DSTEM or macTEM, over stdio. An MCP client (Claude, Codex) starts it and
//  writes one JSON-RPC message per line on its standard input; each answer is one line on standard output. It ends when the
//  input ends. One copy per app:
//
//      claude mcp add mac4dstem -- /path/to/macem-mcp --app mac4DSTEM
//      claude mcp add mactem -- /path/to/macem-mcp --app macTEM
//
//  Standard output carries protocol messages only; anything for a person goes to standard error.
//

import AgentBridgeCore
import Foundation

let arguments = CommandLine.arguments
let names = BridgeApp.known.map(\.name).joined(separator: " or ")

if arguments.contains("--version") {
    print("macem-mcp \(MCPServer.serverVersion)")
    exit(0)
}
if arguments.contains("--help") || arguments.contains("-h") {
    print("""
        macem-mcp \(MCPServer.serverVersion): the MCP bridge to the agent door of \(names).

        Started by an MCP client, which talks to it over standard input and output, one copy per app:
            claude mcp add mac4dstem -- \(arguments[0]) --app mac4DSTEM
            claude mcp add mactem -- \(arguments[0]) --app macTEM

        In the app, turn the door on first: Settings > Agents > "Let agents on this Mac look at open windows".
        The bridge looks; it changes nothing in the app.
        """)
    exit(0)
}

guard let flag = arguments.firstIndex(of: "--app"), flag + 1 < arguments.count, let app = BridgeApp.named(arguments[flag + 1]) else {
    FileHandle.standardError.write(Data("macem-mcp: say which app with --app \(names) (--help for more).\n".utf8))
    exit(64)
}

let server = MCPServer(app: app, door: LocalDoor(app: app))
let output = FileHandle.standardOutput
while let line = readLine(strippingNewline: true) {
    for answer in server.handle(line: line) {
        output.write(Data((answer + "\n").utf8))
    }
}
