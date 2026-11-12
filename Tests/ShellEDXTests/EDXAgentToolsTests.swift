//
//  EDXAgentToolsTests.swift
//  The EDS room's agent tools (ShellEDXAgent) over a real door's MCP route, on the planted spectrum image of EDXSessionTests:
//  an agent picks the elements and the region, quantifies, and reads the table as numbers, as the person's controls would.
//

import XCTest
import SpectroEDX
@testable import ShellAgentDoor
@testable import ShellEDXModel
import ShellEDXAgent

private final class Window {
    let session: EDXSession
    init(_ session: EDXSession) { self.session = session }
}

nonisolated final class EDXAgentToolsTests: XCTestCase {

    @MainActor private func door(_ window: Window) -> AgentDoor {
        let suite = "edx-agent-tools-\(UUID().uuidString)"
        let door = AgentDoor(appName: "TestApp", appVersion: "1.0", preferredPort: 0, defaults: UserDefaults(suiteName: suite)!)
        door.register(EDXAgentTools.tools { ($0 as? Window)?.session })
        door.enroll(window) { [:] }
        door.runsAllowed = true
        return door
    }

    @MainActor private func call(_ door: AgentDoor, _ name: String, _ arguments: [String: Any] = [:]) throws -> (refused: Bool, json: [String: Any], text: String) {
        var request = AgentHTTPRequest(method: "POST", path: "/mcp", headers: ["host": "127.0.0.1:1"])
        request.body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                                   "params": ["name": name, "arguments": arguments]])
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: door.route(request).body) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any], "\(answer)")
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        return (result["isError"] as? Bool ?? true, json, text)
    }

    /// Mutation: set_eds picks the wrong element or ignores the region, run_eds does not quantify, or get_eds leaves out the table - red.
    @MainActor func testAnAgentQuantifiesTheRoomAndReadsTheTable() async throws {
        let empty = Window(EDXSession(host: .test))
        let closed = door(empty)
        XCTAssertTrue(try call(closed, "get_eds").refused, "no spectrum image yet")

        let session = EDXSession(host: .test)
        await session.bind(EDXSessionTests.source()).value
        await session.settled()
        let window = Window(session)
        let door = door(window)

        XCTAssertTrue(try call(door, "set_eds", ["add": "Xx"]).refused, "not an element")
        XCTAssertTrue(try call(door, "set_eds", ["fit_only": "Au"]).refused, "not picked")
        let picked = try call(door, "set_eds", ["remove": session.picks.map(\.symbol).joined(separator: ","), "add": "Al, Mg, Si",
                                                "region": "rectangle", "x0": 0, "y0": 0, "x1": 1, "y1": 1])
        XCTAssertFalse(picked.refused, picked.text)
        await session.settled()
        XCTAssertEqual(Set(session.picks.map(\.symbol)), ["Al", "Mg", "Si"])
        XCTAssertEqual(session.regionPixels, 1, "the left pixel only")

        let started = try call(door, "run_eds", ["action": "quantify"])
        XCTAssertFalse(started.refused, started.text)
        await session.settled()
        XCTAssertNotNil(session.fit, session.fitFailure ?? "")

        let read = try call(door, "get_eds")
        XCTAssertFalse(read.refused, read.text)
        XCTAssertEqual(read.json["busy"] as? Bool, false)
        let csv = try XCTUnwrap(read.json["results_csv"] as? String, read.text)
        XCTAssertEqual(csv, session.resultsCSV, "the table is the room's own CSV")
        XCTAssertTrue(csv.contains("Al") && csv.contains("Mg") && csv.contains("Si"))
        XCTAssertEqual((read.json["picks"] as? [[String: Any]])?.count, 3)

        XCTAssertTrue(try call(door, "set_eds", ["region": "pin", "pin": "nothing"]).refused)
        XCTAssertFalse(try call(door, "set_eds", ["region": "whole"]).refused)
        await session.settled()
        XCTAssertEqual(session.region, .wholeMap)
        withExtendedLifetime(window) {}
        withExtendedLifetime(empty) {}
    }
}
