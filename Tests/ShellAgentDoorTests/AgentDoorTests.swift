// The shared agent door: reading a request, who may ask, the routes, the tool slot, the window list, and the whole way once over
// the loopback address. The apps' own tools are tested in each app.

import CoreGraphics
import Foundation
import XCTest
@testable import ShellAgentDoor

/// Stands in for an app's window state.
private final class Probe {
    let file: String
    init(_ file: String) { self.file = file }
}

@MainActor
final class AgentDoorTests: XCTestCase {

    // MARK: Reading a request

    func testAWholeRequestIsReadWithItsPathQueryAndHeaders() {
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
    func testARequestInPiecesWaitsForItsEndAndItsBody() {
        let whole = Data("POST /v1/x HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\n\r\nhello".utf8)
        for cut in [10, whole.count - 6, whole.count - 1] {
            XCTAssertEqual(AgentHTTP.parse(whole.prefix(cut)), .incomplete, "cut at \(cut)")
        }
        guard case .request(let request) = AgentHTTP.parse(whole) else { return XCTFail("not read as a request") }
        XCTAssertEqual(request.body, Data("hello".utf8))
        let padded = Data("xx".utf8) + whole
        XCTAssertEqual(AgentHTTP.parse(padded.dropFirst(2)), .request(request), "a slice that does not start at 0 reads the same")
    }

    func testWhatIsNotARequestIsRefusedByName() {
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

    func testAResponseStatesItsLengthAndClosesTheConnection() {
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
    func testOnlyTheTokenHolderOnThisMacPasses() {
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

    private func door(_ windows: [Probe] = []) -> AgentDoor {
        let door = AgentDoor(appName: "TestApp", appVersion: "1.0", discoveryURL: nil)
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

    func testTheDoorIsReadOnlyAndNamesItsTools() throws {
        let door = door()
        XCTAssertEqual(door.route(request(method: "POST")).status, 405)
        XCTAssertEqual(door.route(request("/")).status, 404)
        XCTAssertEqual(door.route(request("/v1/nothing")).status, 404)
        XCTAssertEqual(door.route(request("/v1/tools/no_such_tool")).status, 404)
        let index = try object(door.route(request("/v1")))
        XCTAssertEqual(index["access"] as? String, "read-only")
        XCTAssertEqual(index["app"] as? String, "TestApp")
        XCTAssertEqual(index["tools"] as? [String], ["list_windows", "get_file", "get_scale", "get_nothing"], "the door's own first, then the app's in order")
    }

    /// `/v1/tools` is what the bridge passes to MCP's `tools/list` as it stands: the shape must be MCP's.
    func testToolsAreDescribedInMCPsShape() throws {
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
    func testAToolFindsItsWindow() throws {
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

    func testAPictureScaleIsOneTwoOrThree() throws {
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

    func testAPNGIsWrittenFromAPicture() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard case .png(let data) = AgentJSON.picture(context.makeImage()) else { return XCTFail("no PNG") }
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        guard case .refusal(let status, _) = AgentJSON.picture(nil) else { return XCTFail("no picture is a refusal") }
        XCTAssertEqual(status, 500)
        XCTAssertTrue(AgentJSON.number(Double.nan) is NSNull)
        XCTAssertEqual(AgentJSON.number(Float(2.5)) as? Double, 2.5)
    }

    func testToolNamesAreMCPsShape() {
        XCTAssertTrue(AgentTool.isValidName("get_result_image2"))
        XCTAssertFalse(AgentTool.isValidName(""))
        XCTAssertFalse(AgentTool.isValidName("Get"))
        XCTAssertFalse(AgentTool.isValidName("get/image"))
        XCTAssertFalse(AgentTool.isValidName("get-image"))
    }

    // MARK: Windows and Settings

    func testWindowsAreNamedInOrderAndForgottenWhenTheyClose() {
        let door = door()
        let first = Probe("1"), second = Probe("2")
        door.enroll(first) { [:] }; door.enroll(second) { [:] }; door.enroll(first) { [:] }
        XCTAssertEqual(door.liveWindows.map { $0.window.id }, ["w1", "w2"])
        door.withdraw(first)
        XCTAssertEqual(door.liveWindows.map { $0.window.id }, ["w2"])
        door.enroll(first) { [:] }
        XCTAssertEqual(door.liveWindows.map { $0.window.id }, ["w2", "w3"], "a name is never given twice")
    }

    func testAWindowThatIsGoneIsNotListed() {
        let door = door()
        do {
            let passing = Probe("gone")
            door.enroll(passing) { [:] }
            XCTAssertEqual(door.liveWindows.count, 1)
        }
        XCTAssertEqual(door.liveWindows.count, 0, "the door holds a window weakly")
    }

    func testTheStatusRowSaysWhatTheDoorIsDoing() {
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.off, requests: 0), "Off")
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.listening(port: 5000), requests: 0), "On (port 5000), no agent has asked yet")
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.listening(port: 5000), requests: 1), "On (port 5000), 1 request answered")
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.listening(port: 5000), requests: 3), "On (port 5000), 3 requests answered")
        XCTAssertEqual(AgentDoorSettingsSection.statusText(.failed("no"), requests: 0), "Could not open: no")
        XCTAssertTrue(AgentDoorSettingsSection.explanation(appName: "macTEM", canSee: "images").contains("cannot change anything"))
    }

    func testTheTokenIsNewAndLong() {
        let a = AgentDoor.makeToken(), b = AgentDoor.makeToken()
        XCTAssertEqual(a.count, 64)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy(\.isHexDigit))
    }

    // MARK: The whole way once

    /// The door opens on the loopback address, writes its file for this account only, answers the token holder, refuses a request
    /// without the token, and takes its file away when it closes.
    func testTheOpenDoorAnswersOverTheLoopbackAddress() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-door-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("agent-door.json")
        let door = AgentDoor(appName: "TestApp", appVersion: "1.0", discoveryURL: file)
        let probe = Probe("a.h5")
        door.enroll(probe) { ["file_name": probe.file] }
        door.setEnabled(true)
        defer { door.setEnabled(false) }
        for _ in 0..<250 where door.status == .starting || door.status == .off { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening(let port) = door.status else { return XCTFail("the door did not open: \(door.status)") }

        let record = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(record["port"] as? Int, Int(port))
        XCTAssertEqual(record["api"] as? Int, AgentDoor.apiVersion)
        XCTAssertEqual(record["app"] as? String, "TestApp")
        let token = try XCTUnwrap(record["token"] as? String)
        XCTAssertEqual(token.count, 64)
        let permissions = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(permissions & 0o077, 0, "nobody but this account reads the token")

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

        door.setEnabled(false)
        XCTAssertEqual(door.status, .off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "a closed door leaves no file")
    }
}
