// SPDX-License-Identifier: GPL-3.0-only
//
//  Door.swift
//  Role: The bridge's side of an app's agent door: where the door is (two environment variables, which the app's Settings > Agents
//        > Copy Connection Command puts into the `claude mcp add` line) and one GET to it. The door answers on this Mac's loopback
//        address only and wants its token. The app writes no file: a sandboxed app's container is closed to other programs.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One answer from the door.
public struct DoorAnswer {
    public var status: Int
    public var contentType: String
    public var body: Data

    public init(status: Int, contentType: String, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }
}

/// Why the door could not be asked. `message` is a sentence for the agent to pass on.
public struct DoorError: Error, Equatable {
    public var message: String

    public init(_ message: String) { self.message = message }

    /// The door is closed or the app is not running: what the person does about it.
    public static func closed(_ app: BridgeApp) -> DoorError {
        DoorError("\(app.name)'s agent door is not open. Start \(app.name), open Settings > Agents and turn on "
            + "\"Let agents on this Mac look at open windows\".")
    }

    /// The bridge was started without the door's port and token.
    public static func notConnected(_ app: BridgeApp) -> DoorError {
        DoorError("The bridge does not know \(app.name)'s door. In \(app.name), open Settings > Agents, press Copy Connection Command "
            + "and run the copied line in Terminal; it sets \(app.environmentPrefix)_PORT and \(app.environmentPrefix)_TOKEN.")
    }
}

/// Asks the door. A protocol so the server is tested without a port.
public protocol Door {
    func get(_ path: String) throws -> DoorAnswer
}

/// Where the door is: its port and its token.
public struct DoorAddress: Equatable {
    public var port: Int
    public var token: String

    public init(port: Int, token: String) {
        self.port = port
        self.token = token
    }

    /// The door's address from `<APP>_AGENT_PORT` and `<APP>_AGENT_TOKEN`. Throws `DoorError.notConnected` without them.
    public static func find(for app: BridgeApp, environment: [String: String]) throws -> DoorAddress {
        let prefix = app.environmentPrefix
        guard let port = environment["\(prefix)_PORT"].flatMap({ Int($0) }), (1...65535).contains(port),
              let token = environment["\(prefix)_TOKEN"], !token.isEmpty else { throw DoorError.notConnected(app) }
        return DoorAddress(port: port, token: token)
    }
}
/// The real door: the address from the environment, asked over HTTP.
public struct LocalDoor: Door {
    var app: BridgeApp
    var environment: [String: String]

    public init(app: BridgeApp, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.app = app
        self.environment = environment
    }

    public func get(_ path: String) throws -> DoorAnswer {
        let address = try DoorAddress.find(for: app, environment: environment)
        guard let url = URL(string: "http://127.0.0.1:\(address.port)\(path)") else { throw DoorError("Not a path: \(path)") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Bearer \(address.token)", forHTTPHeaderField: "Authorization")

        final class Box: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            done.signal()
        }
        task.resume()
        done.wait()
        guard box.error == nil, let http = box.response as? HTTPURLResponse else {
            // A file from a door that has since closed (the app quit) names a port nobody listens on.
            throw DoorError.closed(app)
        }
        return DoorAnswer(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "",
                          body: box.data ?? Data())
    }
}
