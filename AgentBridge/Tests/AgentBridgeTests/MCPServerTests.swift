// SPDX-License-Identifier: GPL-3.0-only
//
//  The bridge without a port: a door that records what it was asked and answers what the test hands it.
//

import Foundation
import XCTest
@testable import AgentBridgeCore

final class RecordingDoor: Door {
    var answers: [String: DoorAnswer] = [:]
    var failure: DoorError?
    private(set) var asked: [String] = []

    func get(_ path: String) throws -> DoorAnswer {
        asked.append(path)
        if let failure { throw failure }
        return answers[path] ?? DoorAnswer(status: 404, contentType: "application/json", body: Data(#"{"error":"Unknown path."}"#.utf8))
    }

    /// The door lists these tools.
    func lists(_ names: [String]) {
        let tools = names.map { name -> [String: Any] in
            ["name": name, "description": "d", "inputSchema": ["type": "object", "properties": [String: Any]()] as [String: Any],
             "annotations": ["readOnlyHint": true]]
        }
        let body = try! JSONSerialization.data(withJSONObject: ["tools": tools])
        answers["/v1/tools"] = DoorAnswer(status: 200, contentType: "application/json", body: body)
    }
}

final class MCPServerTests: XCTestCase {

    private func json(_ line: String?) throws -> [String: Any] {
        let line = try XCTUnwrap(line)
        XCTAssertFalse(line.contains("\n"), "one message, one line")
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    private func call(_ server: MCPServer, _ tool: String, _ arguments: String = "{}") throws -> [String: Any] {
        let line = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#
        let answer = try json(server.handle(line: line).first)
        XCTAssertEqual(answer["id"] as? Int, 7)
        return try XCTUnwrap(answer["result"] as? [String: Any])
    }

    private func text(_ result: [String: Any]) -> String { (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? "" }

    // MARK: The protocol

    func testInitializeAnswersWithTheAskedVersionAndTheAppsName() throws {
        let server = MCPServer(app: .macTEM, door: RecordingDoor())
        let known = try json(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#).first)
        let result = try XCTUnwrap(known["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual(((result["capabilities"] as? [String: Any])?["tools"] as? [String: Any])?["listChanged"] as? Bool, true)
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "mactem")
        XCTAssertTrue((result["instructions"] as? String ?? "").contains("macTEM's Settings > Agents"))
        let unknown = try json(server.handle(line: #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#).first)
        XCTAssertEqual(unknown["id"] as? String, "a", "the id comes back as it was sent")
        XCTAssertEqual((unknown["result"] as? [String: Any])?["protocolVersion"] as? String, MCPServer.protocolVersions[0])
    }

    func testNotificationsGetNoAnswerAndUnknownMethodsAnError() throws {
        let server = MCPServer(app: .mac4DSTEM, door: RecordingDoor())
        XCTAssertEqual(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#), [])
        XCTAssertEqual(server.handle(line: "   "), [])
        XCTAssertEqual((try json(server.handle(line: "not json").first)["error"] as? [String: Any])?["code"] as? Int, -32700)
        let unknown = try json(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"resources/list"}"#).first)
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertNotNil(try json(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#).first)["result"] as? [String: Any])
        let bad = try json(server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"../v1"}}"#).first)
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    // MARK: The tools are the app's

    /// `tools/list` is the door's `/v1/tools` as it stands; a closed door lists `list_windows` alone, read-only.
    func testTheToolsAreTheDoorsAndAClosedDoorListsOne() throws {
        let door = RecordingDoor()
        let server = MCPServer(app: .mac4DSTEM, door: door)
        func names() throws -> [String] {
            let list = try json(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#).first)
            let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
            for tool in tools {
                XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object")
                XCTAssertEqual((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, true)
            }
            return tools.compactMap { $0["name"] as? String }
        }
        door.failure = .closed(.mac4DSTEM)
        XCTAssertEqual(try names(), ["list_windows"])
        door.failure = nil
        door.lists(["list_windows", "get_window", "get_result_image", "Bad/Name"])
        XCTAssertEqual(try names(), ["list_windows", "get_window", "get_result_image"], "a name that is not a tool name is left out")
    }

    /// The client is told once when the door's tools differ from the list it was given (the app opened after the client started).
    func testTheClientHearsWhenTheListChanges() throws {
        let door = RecordingDoor()
        door.failure = .closed(.macTEM)
        let server = MCPServer(app: .macTEM, door: door)
        _ = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        door.failure = nil
        door.lists(["list_windows", "get_image"])
        door.answers["/v1/tools/list_windows"] = DoorAnswer(status: 200, contentType: "application/json", body: Data(#"{"windows":[]}"#.utf8))
        let line = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_windows"}}"#
        let first = server.handle(line: line)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(try json(first.last)["method"] as? String, "notifications/tools/list_changed")
        XCTAssertEqual(server.handle(line: line).count, 1, "said once")
    }

    func testAToolIsOneGETWithItsWindowAndScale() throws {
        let door = RecordingDoor()
        let json = DoorAnswer(status: 200, contentType: "application/json; charset=utf-8", body: Data(#"{"windows":[]}"#.utf8))
        door.answers["/v1/tools/list_windows"] = json
        door.answers["/v1/tools/get_window"] = json
        door.answers["/v1/tools/get_window?window=w2"] = json
        let server = MCPServer(app: .mac4DSTEM, door: door)
        let list = try call(server, "list_windows")
        XCTAssertEqual(list["isError"] as? Bool, false)
        XCTAssertEqual(text(list), #"{"windows":[]}"#)
        _ = try call(server, "get_window", #"{"window":"current"}"#)
        _ = try call(server, "get_window", #"{"window":"w2"}"#)
        _ = try call(server, "get_result_image", #"{"window":"w1","scale":2}"#)
        _ = try call(server, "get_result_image", #"{"scale":9}"#)
        XCTAssertEqual(door.asked, ["/v1/tools/list_windows", "/v1/tools/get_window", "/v1/tools/get_window?window=w2",
                                    "/v1/tools/get_result_image?window=w1&scale=2", "/v1/tools/get_result_image"])
    }

    /// A picture comes back as MCP image content, base64.
    func testAPictureIsImageContent() throws {
        let door = RecordingDoor()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        door.answers["/v1/tools/get_image"] = DoorAnswer(status: 200, contentType: "image/png", body: png)
        let content = try XCTUnwrap((try call(MCPServer(app: .macTEM, door: door), "get_image")["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(content["type"] as? String, "image")
        XCTAssertEqual(content["mimeType"] as? String, "image/png")
        XCTAssertEqual(Data(base64Encoded: content["data"] as? String ?? ""), png)
    }

    /// What goes wrong is said to the agent in a sentence it can act on, as a tool result, never as a protocol error.
    func testRefusalsAreSentencesInTheResult() throws {
        let door = RecordingDoor()
        let server = MCPServer(app: .macTEM, door: door)
        door.answers["/v1/tools/get_spectrum"] = DoorAnswer(status: 404, contentType: "application/json",
                                                           body: Data(#"{"error":"No spectrum in this window."}"#.utf8))
        let missing = try call(server, "get_spectrum")
        XCTAssertEqual(missing["isError"] as? Bool, true)
        XCTAssertEqual(text(missing), "No spectrum in this window.")

        door.answers["/v1/tools/get_log"] = DoorAnswer(status: 401, contentType: "application/json", body: Data(#"{"error":"Wrong token."}"#.utf8))
        XCTAssertTrue(text(try call(server, "get_log")).contains("Settings > Agents"))

        let before = door.asked.count
        let injected = try call(server, "get_window", #"{"window":"../../v1"}"#)
        XCTAssertEqual(injected["isError"] as? Bool, true)
        XCTAssertEqual(door.asked.count, before, "a window id that is not an id never reaches the door")

        door.failure = .closed(.macTEM)
        let closed = try call(server, "list_windows")
        XCTAssertEqual(closed["isError"] as? Bool, true)
        XCTAssertTrue(text(closed).contains("Start macTEM"))
    }

    // MARK: Finding the door

    func testTheDoorIsFoundFromItsFileOrTheEnvironment() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = BridgeApp.macTEM
        XCTAssertThrowsError(try DoorAddress.find(for: app, environment: [:], home: home)) { XCTAssertEqual($0 as? DoorError, .closed(app)) }

        let files = DoorAddress.candidateFiles(for: app, home: home)
        XCTAssertTrue(files[0].path.contains("Containers/com.mac4dstem.macTEM/Data/Library/Application Support/macTEM/agent-door.json"))
        let contained = files[0], plain = files[1]
        try FileManager.default.createDirectory(at: plain.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"api":1,"port":5001,"token":"plain"}"#.utf8).write(to: plain)
        XCTAssertEqual(try DoorAddress.find(for: app, environment: [:], home: home), DoorAddress(port: 5001, token: "plain"))
        XCTAssertThrowsError(try DoorAddress.find(for: .mac4DSTEM, environment: [:], home: home), "one app's file is not the other's")

        try FileManager.default.createDirectory(at: contained.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"api":1,"port":5002,"token":"contained"}"#.utf8).write(to: contained)
        XCTAssertEqual(try DoorAddress.find(for: app, environment: [:], home: home), DoorAddress(port: 5002, token: "contained"),
                       "the sandboxed app's file first")

        XCTAssertEqual(try DoorAddress.find(for: app, environment: ["MACTEM_AGENT_DOOR": plain.path], home: home).token, "plain")
        XCTAssertEqual(try DoorAddress.find(for: app, environment: ["MACTEM_AGENT_PORT": "6000", "MACTEM_AGENT_TOKEN": "env"], home: home),
                       DoorAddress(port: 6000, token: "env"))
        XCTAssertNil(DoorAddress.parse(Data(#"{"port":0,"token":"x"}"#.utf8)))
        XCTAssertNil(DoorAddress.parse(Data(#"{"port":5000,"token":""}"#.utf8)))
        XCTAssertNil(DoorAddress.parse(Data("not json".utf8)))
    }

    func testTheAppIsNamedInAnyCase() {
        XCTAssertEqual(BridgeApp.named("mactem"), .macTEM)
        XCTAssertEqual(BridgeApp.named("MAC4DSTEM"), .mac4DSTEM)
        XCTAssertNil(BridgeApp.named("velox"))
        XCTAssertEqual(BridgeApp.mac4DSTEM.environmentPrefix, "MAC4DSTEM_AGENT")
    }
}
