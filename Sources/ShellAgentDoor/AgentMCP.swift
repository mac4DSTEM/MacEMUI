//
//  AgentMCP.swift
//  Role: The door's Model Context Protocol endpoint, `POST /mcp`: MCP's Streamable HTTP transport, answered in the app, so an
//        agent connects to the app itself and nothing has to be installed beside it (an App Store app cannot install a
//        command-line tool). JSON-RPC 2.0, one message per request, answered with one JSON response (no event stream):
//        `initialize`, `ping`, `tools/list` (the door's tools as `/v1/tools` lists them) and `tools/call` (the same run as
//        `/v1/tools/<name>`). A notification or a response from the client is accepted with 202 and no body.
//
//  The gate in front of it is the door's (`AgentDoorGate`): loopback only, the token as a Bearer header, no Origin, the door's own
//  Host, which is what MCP's transport asks of a local server. A tool that acts runs only here, never from a GET.
//

import Foundation

extension AgentDoor {
    /// The protocol revisions this endpoint speaks, newest first. A client that asks for one of them gets it; any other the newest.
    static let mcpProtocolVersions = ["2025-06-18", "2025-03-26"]

    /// Answers one request to `/mcp`, the gate passed.
    func mcpResponse(to request: AgentHTTPRequest) -> AgentHTTPResponse {
        guard request.method == "POST" else {
            return .error(405, "POST one JSON-RPC message to /mcp; this server sends no event stream.")
        }
        guard let message = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            return .json(Self.rpcError(NSNull(), -32700, "Parse error: one JSON-RPC message (an object) per request."), status: 400)
        }
        guard let id = message["id"], !(id is NSNull) else {
            return AgentHTTPResponse(status: 202, contentType: "application/json; charset=utf-8", body: Data())
        }
        guard let method = message["method"] as? String else {
            if message["result"] != nil || message["error"] != nil {
                return AgentHTTPResponse(status: 202, contentType: "application/json; charset=utf-8", body: Data())
            }
            return .json(Self.rpcError(id, -32600, "Invalid request"))
        }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return .json(Self.rpcResult(id, [
                "protocolVersion": Self.mcpProtocolVersions.contains(asked) ? asked : Self.mcpProtocolVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": appName.lowercased(), "title": appName, "version": appVersion],
                "instructions": mcpInstructions,
            ]))
        case "ping":
            return .json(Self.rpcResult(id, [String: Any]()))
        case "tools/list":
            return .json(Self.rpcResult(id, ["tools": allTools.map(\.descriptor)]))
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard let tool = allTools.first(where: { $0.name == name }) else {
                return .json(Self.rpcError(id, -32602, "Unknown tool: \(name). tools/list lists them."))
            }
            return .json(Self.rpcResult(id, Self.toolResult(run(tool, query: Self.query(params["arguments"] as? [String: Any] ?? [:])))))
        default:
            return .json(Self.rpcError(id, -32601, "Method not found: \(method)"))
        }
    }

    var mcpInstructions: String {
        "\(appName), an electron microscopy app on this Mac. Read-only tools look at what its open windows show. "
            + "Tools that are not read-only change a window as its own controls do, only while the person allows it in Settings > Agents; "
            + "after one, wait until get_window no longer says busy before the next. "
            + "Start with list_windows; each other tool takes a window id from it (or none while one window is open). "
            + "Judge results by the pictures, not by numbers alone."
    }

    /// A tool call's arguments as the door's query, each as text: a string as given, `true`/`false`, a whole number without a
    /// decimal point, any other number as Swift writes a Double. Anything else (a list, an object, null) is left out.
    nonisolated static func query(_ arguments: [String: Any]) -> [String: String] {
        var query: [String: String] = [:]
        for (key, value) in arguments {
            if let text = value as? String {
                query[key] = text
            } else if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    query[key] = number.boolValue ? "true" : "false"
                } else if number.doubleValue.isFinite, number.doubleValue == number.doubleValue.rounded(), abs(number.doubleValue) < 1e15 {
                    query[key] = String(Int64(number.doubleValue))
                } else {
                    query[key] = String(number.doubleValue)
                }
            }
        }
        return query
    }

    /// A tool's answer as MCP content: a picture as an image, JSON as text, a refusal as an error result whose text says why, so
    /// the agent reads the reason and can act on it (never a protocol error).
    nonisolated static func toolResult(_ answer: AgentHTTPResponse) -> [String: Any] {
        guard answer.status == 200 else {
            let stated = ((try? JSONSerialization.jsonObject(with: answer.body)) as? [String: Any])?["error"] as? String
            return ["content": [["type": "text", "text": stated ?? "The app answered with status \(answer.status)."]], "isError": true]
        }
        if answer.contentType.hasPrefix("image/png") {
            return ["content": [["type": "image", "data": answer.body.base64EncodedString(), "mimeType": "image/png"]], "isError": false]
        }
        return ["content": [["type": "text", "text": String(decoding: answer.body, as: UTF8.self)]], "isError": false]
    }

    nonisolated static func rpcResult(_ id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    nonisolated static func rpcError(_ id: Any, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]]
    }
}
