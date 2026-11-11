// The shared agent door: reading a request, who may ask, the routes, the tool slot, the window list, and the whole way once over
// the loopback address. The apps' own tools are tested in each app.

import CoreGraphics
import Foundation
import XCTest
@testable import ShellAgentDoor

private nonisolated struct DoorDidNotOpen: Error {
    let status: String
}

/// Stands in for an app's window state.
private final class Probe {
    let file: String
    init(_ file: String) { self.file = file }
}

nonisolated final class AgentDoorTests: XCTestCase {

    // MARK: Reading a request

    @MainActor func testAWholeRequestIsReadWithItsPathQueryAndHeaders() {
        let bytes = Data("GET /v1/tools/get_image?window=w1&scale=2 HTTP/1.1\r\nHost: 127.0.0.1:5000\r\nAuthorization: Bearer abc\r\n\r\n".utf8)
        guard case .request(let request) = AgentHTTP.parse(bytes) else { return XCTFail("not read as a request") }
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/v1/tools/get_image")
        XCTAssertEqual(request.query, ["window": "w1", "scale": "2"])
        XCTAssertEqual(request.headers["host"], "127.0.0.1:5000")
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
        XCTAssertTrue(request.body.isEmpty)
    }

    /// Bytes arrive in pieces: until the blank line and the stated body are there, the answer is "more", never a guess.
    @MainActor func testARequestInPiecesWaitsForItsEndAndItsBody() {
        let whole = Data("POST /v1/x HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\n\r\nhello".utf8)
        for cut in [10, whole.count - 6, whole.count - 1] {
            XCTAssertEqual(AgentHTTP.parse(whole.prefix(cut)), .incomplete, "cut at \(cut)")
        }
        guard case .request(let request) = AgentHTTP.parse(whole) else { return XCTFail("not read as a request") }
        XCTAssertEqual(request.body, Data("hello".utf8))
        let padded = Data("xx".utf8) + whole
        XCTAssertEqual(AgentHTTP.parse(padded.dropFirst(2)), .request(request), "a slice that does not start at 0 reads the same")
    }

    @MainActor func testWhatIsNotARequestIsRefusedByName() {
        func malformed(_ text: String) -> Bool {
            if case .malformed = AgentHTTP.parse(Data(text.utf8)) { return true }
            return false
        }
        XCTAssertTrue(malformed("hello\r\n\r\n"))
        XCTAssertTrue(malformed("GET nopath HTTP/1.1\r\n\r\n"))
        XCTAssertTrue(malformed("GET / HTTP/1.1\r\nbroken header\r\n\r\n"))
        XCTAssertTrue(malformed("POST / HTTP/1.1\r\nContent-Length: many\r\n\r\n"))
        XCTAssertTrue(malformed("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"))
        XCTAssertTrue(malformed("POST / HTTP/1.1\r\nContent-Length: \(AgentHTTP.maximumBodyBytes + 1)\r\n\r\n"))
        XCTAssertTrue(malformed("GET /" + String(repeating: "a", count: AgentHTTP.maximumHeaderBytes + 10)), "headers that never end are cut off")
    }

    @MainActor func testAResponseStatesItsLengthAndClosesTheConnection() {
        let response = AgentHTTPResponse.json(["b": 1, "a": "x"])
        let wire = String(decoding: response.serialized(), as: UTF8.self)
        XCTAssertTrue(wire.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(wire.contains("Content-Length: \(response.body.count)\r\n"))
        XCTAssertTrue(wire.contains("Connection: close\r\n"))
        XCTAssertTrue(wire.hasSuffix("\r\n\r\n{\"a\":\"x\",\"b\":1}"), "sorted keys, the body after one blank line")
        XCTAssertEqual(AgentHTTPResponse.json(["x": Double.nan]).status, 500, "a number JSON cannot carry is a 500, not an exception")
    }

    // MARK: Who may ask

    private func request(_ path: String = "/v1", method: String = "GET", token: String? = "secret", host: String = "127.0.0.1:5000",
                         origin: String? = nil, query: [String: String] = [:]) -> AgentHTTPRequest {
        var headers = ["host": host]
        if let token { headers["authorization"] = "Bearer \(token)" }
        if let origin { headers["origin"] = origin }
        return AgentHTTPRequest(method: method, path: path, query: query, headers: headers)
    }

    /// Mutation: drop any one of the three checks in `AgentDoorGate.refusal` and one line here goes red.
    @MainActor func testOnlyTheTokenHolderOnThisMacPasses() {
        func status(_ request: AgentHTTPRequest) -> Int? { AgentDoorGate.refusal(for: request, token: "secret", port: 5000)?.status }
        XCTAssertNil(status(request()))
        XCTAssertNil(status(request(host: "localhost:5000")))
        XCTAssertEqual(status(request(token: nil)), 401)
        XCTAssertEqual(status(request(token: "secreT")), 401)
        XCTAssertEqual(status(request(token: "secret-and-more")), 401)
        XCTAssertEqual(status(request(host: "evil.example:5000")), 403, "a page that reached the port through its own DNS name")
        XCTAssertEqual(status(request(host: "127.0.0.1:5001")), 403)
        XCTAssertEqual(status(request(origin: "https://example.com")), 403, "a web page, token or not")
        XCTAssertEqual(AgentDoorGate.refusal(for: request(token: ""), token: "", port: 5000)?.status, 401, "an empty token opens nothing")
    }

    // MARK: Routes and the tool slot

    @MainActor private func door(_ windows: [Probe] = []) -> AgentDoor {
        let door = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: Self.freshDefaults())
        door.register([
            AgentTool(name: "get_file", title: "File", summary: "The window's file.", input: .window) { call in
                guard let probe = call.window?.state as? Probe else { return .refusal(status: 500, message: "not a probe") }
                return .json(["file": probe.file, "window": call.window?.id ?? ""])
            },
            AgentTool(name: "get_scale", title: "Scale", summary: "The scale asked for.", input: .windowPicture) { call in
                .json(["scale": call.scale])
            },
            AgentTool(name: "get_nothing", title: "Nothing", summary: "Nothing yet.", input: .noWindow) { _ in
                .refusal(status: 404, message: "Nothing to show yet.")
            },
        ])
        for probe in windows { door.enroll(probe) { ["file_name": probe.file] } }
        return door
    }

    private func object(_ response: AgentHTTPResponse) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    @MainActor func testTheDoorIsReadOnlyAndNamesItsTools() throws {
        let door = door()
        XCTAssertEqual(door.route(request(method: "POST")).status, 405, "the /v1 routes are GETs")
        XCTAssertEqual(door.route(request("/")).status, 404)
        XCTAssertEqual(door.route(request("/v1/nothing")).status, 404)
        XCTAssertEqual(door.route(request("/v1/tools/no_such_tool")).status, 404)
        let index = try object(door.route(request("/v1")))
        XCTAssertEqual(index["access"] as? String, "read-only")
        XCTAssertEqual(index["app"] as? String, "TestApp")
        XCTAssertEqual(index["tools"] as? [String], ["list_windows", "get_file", "get_scale", "get_nothing"], "the door's own first, then the app's in order")
    }

    /// `/v1/tools` is what MCP's `tools/list` answers: the shape must be MCP's.
    @MainActor func testToolsAreDescribedInMCPsShape() throws {
        let tools = try XCTUnwrap(try object(door().route(request("/v1/tools")))["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 4)
        for tool in tools {
            XCTAssertNotNil(tool["name"] as? String)
            XCTAssertNotNil(tool["description"] as? String)
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object")
            XCTAssertEqual((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, true)
        }
        func properties(_ name: String) -> [String] {
            let tool = tools.first { $0["name"] as? String == name }
            return ((tool?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])?.keys.sorted() ?? ["missing"]
        }
        XCTAssertEqual(properties("list_windows"), [])
        XCTAssertEqual(properties("get_file"), ["window"])
        XCTAssertEqual(properties("get_scale"), ["scale", "window"])
    }

    /// No window named: the only open one. With none or several, the refusal says which there are.
    @MainActor func testAToolFindsItsWindow() throws {
        let a = Probe("a.h5"), b = Probe("b.h5")
        XCTAssertEqual(door().route(request("/v1/tools/get_file")).status, 404, "no window open")
        let one = door([a])
        XCTAssertEqual(try object(one.route(request("/v1/tools/get_file")))["file"] as? String, "a.h5")
        XCTAssertEqual(try object(one.route(request("/v1/tools/get_file", query: ["window": "current"])))["file"] as? String, "a.h5")
        let two = door([a, b])
        let ambiguous = two.route(request("/v1/tools/get_file"))
        XCTAssertEqual(ambiguous.status, 409)
        XCTAssertTrue(String(decoding: ambiguous.body, as: UTF8.self).contains("w2 (b.h5)"), "the refusal names the windows")
        XCTAssertEqual(try object(two.route(request("/v1/tools/get_file", query: ["window": "w2"])))["file"] as? String, "b.h5")
        XCTAssertEqual(two.route(request("/v1/tools/get_file", query: ["window": "w9"])).status, 404)
        XCTAssertEqual(two.route(request("/v1/tools/get_nothing")).status, 404, "a tool's refusal keeps its status")
        let list = try XCTUnwrap(try object(two.route(request("/v1/tools/list_windows")))["windows"] as? [[String: Any]])
        XCTAssertEqual(list.map { $0["id"] as? String }, ["w1", "w2"])
        XCTAssertEqual(list.map { $0["file_name"] as? String }, ["a.h5", "b.h5"])
    }

    @MainActor func testAPictureScaleIsOneTwoOrThree() throws {
        let door = door([Probe("a.h5")])
        func scale(_ stated: String?) throws -> Int? {
            try object(door.route(request("/v1/tools/get_scale", query: stated.map { ["scale": $0] } ?? [:])))["scale"] as? Int
        }
        XCTAssertEqual(try scale(nil), 1)
        XCTAssertEqual(try scale("2"), 2)
        XCTAssertEqual(try scale("3"), 3)
        XCTAssertEqual(try scale("4"), 1)
        XCTAssertEqual(try scale("x"), 1)
    }

    @MainActor func testAPNGIsWrittenFromAPicture() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard case .png(let data) = AgentJSON.picture(context.makeImage()) else { return XCTFail("no PNG") }
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        guard case .refusal(let status, _) = AgentJSON.picture(nil) else { return XCTFail("no picture is a refusal") }
        XCTAssertEqual(status, 500)
        XCTAssertTrue(AgentJSON.number(Double.nan) is NSNull)
        XCTAssertEqual(AgentJSON.number(Float(2.5)) as? Double, 2.5)
    }

    @MainActor func testToolNamesAreMCPsShape() {
        XCTAssertTrue(AgentTool.isValidName("get_result_image2"))
        XCTAssertFalse(AgentTool.isValidName(""))
        XCTAssertFalse(AgentTool.isValidName("Get"))
        XCTAssertFalse(AgentTool.isValidName("get/image"))
        XCTAssertFalse(AgentTool.isValidName("get-image"))
    }

    // MARK: Windows and Settings

    @MainActor func testWindowsAreNamedInOrderAndForgottenWhenTheyClose() {
        let door = door()
        let first = Probe("1"), second = Probe("2")
        door.enroll(first) { [:] }; door.enroll(second) { [:] }; door.enroll(first) { [:] }
        XCTAssertEqual(door.liveWindows.map { $0.window.id }, ["w1", "w2"])
        door.withdraw(first)
        XCTAssertEqual(door.liveWindows.map { $0.window.id }, ["w2"])
        door.enroll(first) { [:] }
        XCTAssertEqual(door.liveWindows.map { $0.window.id }, ["w2", "w3"], "a name is never given twice")
    }

    @MainActor func testAWindowThatIsGoneIsNotListed() {
        let door = door()
        do {
            let passing = Probe("gone")
            door.enroll(passing) { [:] }
            XCTAssertEqual(door.liveWindows.count, 1)
        }
        XCTAssertEqual(door.liveWindows.count, 0, "the door holds a window weakly")
    }

    @MainActor func testTheStatusRowSaysWhatTheDoorIsDoing() {
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.off, requests: 0), "Off")
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.listening(port: 5000), requests: 0), "On (port 5000), no agent has asked yet")
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.listening(port: 5000), requests: 1), "On (port 5000), 1 request answered")
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.listening(port: 5000), requests: 3), "On (port 5000), 3 requests answered")
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.failed("no"), requests: 0), "Could not open: no")
        XCTAssertTrue(AgentDoorSettingsSection.explanation(appName: "macTEM", canSee: "images").contains("cannot change anything"))
        let runs = AgentDoorSettingsSection.explanation(appName: "mac4DSTEM", canSee: "maps", canRun: "run disk detection")
        XCTAssertTrue(runs.contains("it can also run disk detection"))
        XCTAssertTrue(runs.contains("Stop in the window cancels it"))
        XCTAssertFalse(runs.contains("cannot change anything"))
    }

    @MainActor func testTheTokenIsNewAndLong() {
        let a = AgentDoor.makeToken(), b = AgentDoor.makeToken()
        XCTAssertEqual(a.count, 64)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy(\.isHexDigit))
    }

    // MARK: The whole way once

    /// A suite of its own per door, removed after the test.
    nonisolated private static func freshDefaults() -> UserDefaults {
        let suite = "agent-door-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// The token is made once and kept, so a copied command stays good across launches; New Token replaces it.
    /// Red under: a token made each time the door opens (the old design), or New Token that does not persist.
    @MainActor func testTheTokenIsKeptUntilANewOneIsMade() {
        let defaults = Self.freshDefaults()
        let first = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: defaults)
        XCTAssertTrue(AgentDoor.isToken(first.token))
        let again = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: defaults)
        XCTAssertEqual(again.token, first.token, "the same token after a relaunch")
        again.makeNewToken()
        XCTAssertNotEqual(again.token, first.token)
        XCTAssertEqual(AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: defaults).token, again.token)
        defaults.set("not a token", forKey: AgentDoor.tokenKey)
        XCTAssertTrue(AgentDoor.isToken(AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: defaults).token),
                      "a damaged stored token is replaced")
    }

    @MainActor private func waitUntilOpen(_ door: AgentDoor) async throws -> UInt16 {
        for _ in 0..<250 where door.status == .starting || door.status == .off { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening(let port) = door.status else { throw DoorDidNotOpen(status: "\(door.status)") }
        return port
    }

    /// The door takes the app's port when it is free; a second door asking for the same port gets another, and says which.
    /// Red under: the preferred port ignored (the first assertion), or a taken port ending in "Could not open" (the second).
    @MainActor func testTheAppsPortIsAskedForFirstAndATakenOneIsReplaced() async throws {
        // A port that is free now: the system's pick, released again.
        let probe = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: Self.freshDefaults())
        probe.setEnabled(true)
        let free = try await waitUntilOpen(probe)
        probe.setEnabled(false)
        try await Task.sleep(for: .milliseconds(300))

        let first = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: free, defaults: Self.freshDefaults())
        first.setEnabled(true)
        defer { first.setEnabled(false) }
        let taken = try await waitUntilOpen(first)
        XCTAssertEqual(taken, free, "a free preferred port is the one taken")

        let second = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: free, defaults: Self.freshDefaults())
        second.setEnabled(true)
        defer { second.setEnabled(false) }
        let other = try await waitUntilOpen(second)
        XCTAssertNotEqual(other, free)
    }

    /// The command registers the app itself as an HTTP MCP server: its address on the port in use and the token; none while the
    /// door is shut.
    @MainActor func testTheConnectionCommandCarriesPortAndToken() async throws {
        let door = AgentDoor(appName: "macTEM", appVersion: "1.0", preferredPort: 0, defaults: Self.freshDefaults())
        XCTAssertNil(door.connectionCommand())
        door.setEnabled(true)
        defer { door.setEnabled(false) }
        let port = try await waitUntilOpen(door)
        XCTAssertEqual(door.connectionCommand(),
                       "claude mcp add --transport http mactem http://127.0.0.1:\(port)/mcp --header \"Authorization: Bearer \(door.token)\"")
    }

    // MARK: MCP

    private func mcp(_ message: [String: Any]) throws -> AgentHTTPRequest {
        var asked = request("/mcp", method: "POST")
        asked.body = try JSONSerialization.data(withJSONObject: message)
        return asked
    }

    private func result(_ response: AgentHTTPResponse) throws -> [String: Any] {
        XCTAssertEqual(response.status, 200)
        return try XCTUnwrap(try object(response)["result"] as? [String: Any], String(decoding: response.body, as: UTF8.self))
    }

    /// The handshake and the list: the client's revision when the door speaks it, the tools as `/v1/tools` lists them.
    @MainActor func testMCPStartsAndListsTheTools() throws {
        let door = door()
        let started = try result(door.route(try mcp(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                                     "params": ["protocolVersion": "2025-03-26", "capabilities": [String: Any]()]])))
        XCTAssertEqual(started["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((started["serverInfo"] as? [String: Any])?["name"] as? String, "testapp")
        XCTAssertNotNil((started["capabilities"] as? [String: Any])?["tools"])
        let newest = try result(door.route(try mcp(["jsonrpc": "2.0", "id": 2, "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])))
        XCTAssertEqual(newest["protocolVersion"] as? String, AgentDoor.mcpProtocolVersions[0])
        let listed = try result(door.route(try mcp(["jsonrpc": "2.0", "id": "a", "method": "tools/list"])))
        XCTAssertEqual((listed["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String },
                       ["list_windows", "get_file", "get_scale", "get_nothing"])
        let pong = try object(door.route(try mcp(["jsonrpc": "2.0", "id": 7, "method": "ping"])))
        XCTAssertEqual(pong["id"] as? Int, 7, "the answer carries the request's id")
    }

    /// A call runs the tool with its window and scale; a refusal is a result the agent reads (`isError`), never a protocol error.
    @MainActor func testMCPCallsRunTheToolsAndRefusalsAreReadable() throws {
        let door = door([Probe("a.h5"), Probe("b.h5")])
        func call(_ name: String, _ arguments: [String: Any] = [:]) throws -> [String: Any] {
            try result(door.route(try mcp(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": name, "arguments": arguments]])))
        }
        func text(_ answer: [String: Any]) -> String { ((answer["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "" }
        let file = try call("get_file", ["window": "w2"])
        XCTAssertEqual(file["isError"] as? Bool, false)
        XCTAssertTrue(text(file).contains("b.h5"))
        XCTAssertTrue(text(try call("get_scale", ["window": "w1", "scale": 2])).contains("\"scale\":2"))
        let several = try call("get_file")
        XCTAssertEqual(several["isError"] as? Bool, true)
        XCTAssertTrue(text(several).contains("w1"), "the refusal names the windows to choose from")
        XCTAssertEqual(text(try call("get_nothing")), "Nothing to show yet.")
        let unknown = try object(door.route(try mcp(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "rm_rf"]])))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    @MainActor func testMCPAnswersWhatItIsNotSent() throws {
        let door = door()
        XCTAssertEqual(door.route(try mcp(["jsonrpc": "2.0", "method": "notifications/initialized"])).status, 202, "a notification")
        XCTAssertTrue(door.route(try mcp(["jsonrpc": "2.0", "method": "notifications/initialized"])).body.isEmpty)
        XCTAssertEqual(door.route(request("/mcp")).status, 405, "no event stream")
        var garbled = request("/mcp", method: "POST")
        garbled.body = Data("{nope".utf8)
        XCTAssertEqual(door.route(garbled).status, 400)
        let unknown = try object(door.route(try mcp(["jsonrpc": "2.0", "id": 5, "method": "resources/list"])))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    /// A tool that acts runs only through MCP, only while the person allows it, and only with inputs that pass its schema; it is
    /// listed as not read-only (never destructive) so the agent's client asks the person first.
    /// Mutation: `run` ignores `runsAllowed`, the GET route runs it, or a parameter is not checked - red.
    @MainActor func testAToolThatActsRunsOnlyThroughMCPWhileThePersonAllowsIt() throws {
        let door = door([Probe("a.h5")])
        final class Calls { var arguments: [[String: String]] = [] }
        let calls = Calls()
        door.register([
            AgentTool(name: "run_detection", title: "Run detection", summary: "Detects disks.", input: .window,
                      parameters: [AgentParameter("threshold", .number(0...1), summary: "Correlation threshold.", required: true),
                                   AgentParameter("method", .choice(["fast", "full"]), summary: "How."),
                                   AgentParameter("subpixel", .boolean, summary: "Refine."),
                                   AgentParameter("count", .integer(1...9), summary: "How many.")],
                      acts: true) { call in
                calls.arguments.append(call.arguments)
                return .json(["started": true])
            },
        ])
        func call(_ arguments: [String: Any]) throws -> [String: Any] {
            try result(door.route(try mcp(["jsonrpc": "2.0", "id": 9, "method": "tools/call",
                                           "params": ["name": "run_detection", "arguments": arguments]])))
        }
        func text(_ answer: [String: Any]) -> String { ((answer["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "" }

        let listed = try XCTUnwrap(try object(door.route(request("/v1/tools")))["tools"] as? [[String: Any]])
        let tool = try XCTUnwrap(listed.first { $0["name"] as? String == "run_detection" })
        let annotations = try XCTUnwrap(tool["annotations"] as? [String: Any])
        XCTAssertEqual(annotations["readOnlyHint"] as? Bool, false)
        XCTAssertEqual(annotations["destructiveHint"] as? Bool, false)
        let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["threshold"])
        let threshold = try XCTUnwrap((schema["properties"] as? [String: Any])?["threshold"] as? [String: Any])
        XCTAssertEqual(threshold["type"] as? String, "number")
        XCTAssertEqual(threshold["maximum"] as? Double, 1)

        let refused = try call(["threshold": 0.5])
        XCTAssertEqual(refused["isError"] as? Bool, true)
        XCTAssertTrue(text(refused).contains("Let agents run analyses"), "the refusal says how to allow it")
        XCTAssertEqual(try object(door.route(request("/v1")))["access"] as? String, "read-only")
        door.runsAllowed = true
        XCTAssertEqual(try object(door.route(request("/v1")))["access"] as? String, "look and run")
        XCTAssertEqual(door.route(request("/v1/tools/run_detection")).status, 405, "never from a GET")
        XCTAssertTrue(calls.arguments.isEmpty)

        XCTAssertTrue(text(try call([:])).contains("threshold is required"))
        XCTAssertTrue(text(try call(["threshold": 2])).contains("between 0.0 and 1.0"))
        XCTAssertTrue(text(try call(["threshold": "high"])).contains("must be a number"))
        XCTAssertTrue(text(try call(["threshold": 0.5, "method": "slow"])).contains("one of fast, full"))
        XCTAssertTrue(text(try call(["threshold": 0.5, "count": 2.5])).contains("whole number"))
        XCTAssertTrue(calls.arguments.isEmpty, "nothing ran on a refused input")

        let started = try call(["threshold": 0.25, "method": "full", "subpixel": true, "count": 3])
        XCTAssertEqual(started["isError"] as? Bool, false)
        XCTAssertEqual(calls.arguments, [["threshold": "0.25", "method": "full", "subpixel": "true", "count": "3"]])
    }

    /// A picture comes back as MCP image content, base64 PNG.
    @MainActor func testMCPPicturesAreImages() throws {
        let answer = AgentDoor.toolResult(.png(Data([0x89, 0x50, 0x4E, 0x47])))
        let content = try XCTUnwrap((answer["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(content["type"] as? String, "image")
        XCTAssertEqual(content["mimeType"] as? String, "image/png")
        XCTAssertEqual(content["data"] as? String, Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())
        XCTAssertEqual(AgentDoor.query(["window": "w3", "scale": 2.0]), ["window": "w3", "scale": "2"])
    }

    /// The door opens on the loopback address, answers the token holder and refuses a request without the token.
    @MainActor func testTheOpenDoorAnswersOverTheLoopbackAddress() async throws {
        let door = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: Self.freshDefaults())
        let probe = Probe("a.h5")
        door.enroll(probe) { ["file_name": probe.file] }
        door.setEnabled(true)
        defer { door.setEnabled(false) }
        let port = try await waitUntilOpen(door)
        let token = door.token

        let session = URLSession(configuration: .ephemeral)
        var asked = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/tools/list_windows")))
        asked.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: asked)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let list = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((list["windows"] as? [[String: Any]])?.first?["id"] as? String, "w1")
        XCTAssertEqual(door.requestCount, 1)

        let (_, refused) = try await session.data(for: URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/tools"))))
        XCTAssertEqual((refused as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertEqual(door.requestCount, 1, "a refused request is not counted as answered")

        var mcpCall = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
        mcpCall.httpMethod = "POST"
        mcpCall.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        mcpCall.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mcpCall.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        mcpCall.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_windows","arguments":{}}}"#.utf8)
        let (mcpData, mcpResponse) = try await session.data(for: mcpCall)
        XCTAssertEqual((mcpResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: mcpData, as: UTF8.self).contains("a.h5"), "MCP over the loopback address, as Claude Code asks")

        door.setEnabled(false)
        XCTAssertEqual(door.status, .off)
        XCTAssertEqual(door.token, token, "closing keeps the token")
    }
}
