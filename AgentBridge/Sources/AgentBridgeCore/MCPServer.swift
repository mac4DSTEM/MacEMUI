// SPDX-License-Identifier: GPL-3.0-only
//
//  MCPServer.swift
//  Role: The Model Context Protocol side of the bridge: JSON-RPC 2.0 messages, one per line (the stdio transport), answered
//        from the app's agent door. The tools are the app's: `tools/list` passes on the door's `/v1/tools` as it stands and
//        `tools/call` is one GET to `/v1/tools/<name>`, so the bridge holds no tool of its own, decides nothing about the
//        science, and needs no change when an app adds a tool.
//
//  While the app is closed the list is the door's own `list_windows` alone (its answer says how to open the door); once the
//  door answers with more, the server tells the client the list changed (`notifications/tools/list_changed`).
//
//  Read-only, like the door it speaks to: every tool looks, none changes the app.
//

import Foundation

public final class MCPServer {
    /// The protocol revisions this server speaks, newest first. A client that asks for one of them gets it; any other gets the newest.
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverVersion = "0.1.0"

    let app: BridgeApp
    let door: Door
    /// The names the client was last given, so a change is announced once.
    private var listed: [String]?

    public init(app: BridgeApp, door: Door) {
        self.app = app
        self.door = door
    }

    // MARK: Messages

    /// Answers one line from the client: the lines to write back, none for a notification (a message without an id) or a blank line.
    public func handle(line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let message = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
            return [Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"] as [String: Any]])]
        }
        guard let id = message["id"], !(id is NSNull) else { return [] }
        guard let method = message["method"] as? String else {
            return [Self.error(id, -32600, "Invalid request")]
        }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return [Self.result(id, initialize(params))]
        case "ping":
            return [Self.result(id, [String: Any]())]
        case "tools/list":
            let tools = currentTools()
            listed = tools.compactMap { $0["name"] as? String }
            return [Self.result(id, ["tools": tools])]
        case "tools/call":
            guard let name = params["name"] as? String, Self.isToolName(name) else {
                return [Self.error(id, -32602, "Unknown tool: \(params["name"] as? String ?? "")")]
            }
            var lines = [Self.result(id, call(name, arguments: params["arguments"] as? [String: Any] ?? [:]))]
            if let changed = listChangedNotice() { lines.append(changed) }
            return lines
        default:
            return [Self.error(id, -32601, "Method not found: \(method)")]
        }
    }

    private func initialize(_ params: [String: Any]) -> [String: Any] {
        let asked = params["protocolVersion"] as? String ?? ""
        return [
            "protocolVersion": Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0],
            "capabilities": ["tools": ["listChanged": true]],
            "serverInfo": ["name": app.serverName, "title": app.name, "version": Self.serverVersion],
            "instructions": instructions,
        ]
    }

    var instructions: String {
        "\(app.about) These tools look at what its open windows show; they change nothing. Start with list_windows; "
            + "each other tool takes a window id from it (or none while one window is open). Judge results by the pictures, "
            + "not by numbers alone. If a tool says the agent door is not open, ask the person to turn it on in \(app.name)'s "
            + "Settings > Agents."
    }

    // MARK: Tools

    /// The door's own tool, which the bridge lists while the door is closed: calling it says how to open the door.
    var closedDoorTools: [[String: Any]] {
        [[
            "name": "list_windows",
            "title": "List windows",
            "description": "The open \(app.name) windows, one line each: the id the other tools take, the file, what the window shows. "
                + "\(app.name)'s other tools appear once its agent door is open.",
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false] as [String: Any],
            "annotations": ["title": "List windows", "readOnlyHint": true, "openWorldHint": false] as [String: Any],
        ]]
    }

    /// The app's tools as its door describes them, or the closed door's list.
    func currentTools() -> [[String: Any]] {
        guard let answer = try? door.get("/v1/tools"), answer.status == 200,
              let tools = ((try? JSONSerialization.jsonObject(with: answer.body)) as? [String: Any])?["tools"] as? [[String: Any]],
              !tools.isEmpty else { return closedDoorTools }
        return tools.filter { ($0["name"] as? String).map(Self.isToolName) ?? false }
    }

    /// The notice that the tool list changed, when the door now lists other tools than the client was given.
    private func listChangedNotice() -> String? {
        guard let listed else { return nil }
        let now = currentTools().compactMap { $0["name"] as? String }
        guard now != listed else { return nil }
        self.listed = now
        return Self.encode(["jsonrpc": "2.0", "method": "notifications/tools/list_changed"])
    }

    /// Lowercase letters, digits and underscores: a tool name, and a path segment as it stands.
    static func isToolName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    /// The door's path for one call, or the sentence that says what is wrong with its arguments.
    static func path(for name: String, arguments: [String: Any]) -> Result<String, DoorError> {
        var query: [String] = []
        if let window = arguments["window"] as? String, window != "current", !window.isEmpty {
            guard window.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                return .failure(DoorError("Not a window id: \(window). Use an id from list_windows."))
            }
            query.append("window=\(window)")
        }
        if let scale = arguments["scale"] as? Int, (1...3).contains(scale) { query.append("scale=\(scale)") }
        return .success("/v1/tools/\(name)" + (query.isEmpty ? "" : "?" + query.joined(separator: "&")))
    }

    /// Runs one tool: a GET to the door, its answer as MCP content. A refusal is a result with `isError`, so the agent reads the
    /// reason and can act on it; it is never a protocol error.
    func call(_ name: String, arguments: [String: Any]) -> [String: Any] {
        let answer: DoorAnswer
        do {
            answer = try door.get(try Self.path(for: name, arguments: arguments).get())
        } catch let error as DoorError {
            return Self.refusal(error.message)
        } catch {
            return Self.refusal(DoorError.closed(app).message)
        }
        guard answer.status == 200 else {
            let stated = ((try? JSONSerialization.jsonObject(with: answer.body)) as? [String: Any])?["error"] as? String
            if answer.status == 401 || answer.status == 403 {
                return Self.refusal("\(app.name) refused the bridge (\(stated ?? "status \(answer.status)")). "
                    + "Turn the agent door off and on again in Settings > Agents.")
            }
            return Self.refusal(stated ?? "\(app.name) answered with status \(answer.status).")
        }
        if answer.contentType.hasPrefix("image/png") {
            return ["content": [["type": "image", "data": answer.body.base64EncodedString(), "mimeType": "image/png"]], "isError": false]
        }
        return ["content": [["type": "text", "text": String(decoding: answer.body, as: UTF8.self)]], "isError": false]
    }

    static func refusal(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    // MARK: JSON

    static func result(_ id: Any, _ result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    static func error(_ id: Any, _ code: Int, _ message: String) -> String {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]])
    }

    /// One line of JSON: no newline inside it (the transport's frame is the line).
    static func encode(_ message: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{"error":{"code":-32603,"message":"Internal error"},"id":null,"jsonrpc":"2.0"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
