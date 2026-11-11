//
//  AgentHTTP.swift
//  Role: The little of HTTP/1.1 the agent door speaks (`AgentDoor.swift`): one request per connection, read whole, answered
//        whole, closed. Pure values and pure functions, so the tests read the same parser and the same bytes the listener does.
//
//  Not a web server: no keep-alive, no chunked bodies, no TLS (the listener is bound to this Mac's loopback address and
//  every request carries the door's token). A request it does not understand is refused by name, never guessed at.
//

import Foundation

/// One request as the door read it: the path percent-decoded and without its query, header names lowercased.
nonisolated struct AgentHTTPRequest: Equatable, Sendable {
    var method: String
    var path: String
    var query: [String: String] = [:]
    var headers: [String: String] = [:]
    var body = Data()
}

/// What the bytes received so far amount to.
nonisolated enum AgentHTTPParse: Equatable, Sendable {
    /// More bytes are needed.
    case incomplete
    case request(AgentHTTPRequest)
    /// Not a request the door reads; the text says why and goes back to the caller as a 400.
    case malformed(String)
}

nonisolated enum AgentHTTP {
    /// A request line and its headers fit in this, or the request is refused.
    static let maximumHeaderBytes = 16 * 1024
    /// A request body (step one sends none) fits in this, or the request is refused.
    static let maximumBodyBytes = 1024 * 1024

    private static let headerEnd = Data([13, 10, 13, 10])

    /// Reads one request from the start of `received`. Bytes after the request's body are ignored (one request per connection).
    static func parse(_ received: Data) -> AgentHTTPParse {
        let buffer = Data(received)   // indices from 0, whatever slice the caller holds
        guard let end = buffer.range(of: headerEnd) else {
            return buffer.count > maximumHeaderBytes ? .malformed("The request's headers are too large.") : .incomplete
        }
        guard end.lowerBound <= maximumHeaderBytes else { return .malformed("The request's headers are too large.") }
        let head = String(decoding: buffer.subdata(in: 0..<end.lowerBound), as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .malformed("Not an HTTP/1.1 request line.") }
        let target = requestLine[1]
        guard target.hasPrefix("/"), let components = URLComponents(string: "http://localhost" + target) else {
            return .malformed("The request target is not a path.")
        }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .malformed("A header line has no colon.") }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil else { return .malformed("Chunked request bodies are not read; send Content-Length.") }
        var length = 0
        if let stated = headers["content-length"] {
            guard let parsed = Int(stated), parsed >= 0 else { return .malformed("Content-Length is not a number.") }
            guard parsed <= maximumBodyBytes else { return .malformed("The request body is too large.") }
            length = parsed
        }
        let bodyStart = end.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return .request(AgentHTTPRequest(method: requestLine[0].uppercased(), path: components.path, query: query, headers: headers,
                                         body: buffer.subdata(in: bodyStart..<(bodyStart + length))))
    }
}

/// One answer: a status, a content type and the bytes.
nonisolated struct AgentHTTPResponse: Equatable, Sendable {
    var status: Int
    var contentType: String
    var body: Data

    /// A JSON answer with sorted keys (byte-stable for one state). An object JSON cannot carry (a NaN that slipped through) is a
    /// 500 that says so, never an exception: `JSONSerialization` raises one for an invalid object.
    static func json(_ object: Any, status: Int = 200) -> AgentHTTPResponse {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return error(500, "The answer could not be written as JSON.")
        }
        return AgentHTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    /// Already-encoded JSON (a `Codable` value's own encoding).
    static func json(encoded data: Data) -> AgentHTTPResponse {
        AgentHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: data)
    }

    /// A refusal: `{"error": message}`. The message is a sentence an agent can act on or pass to the person.
    static func error(_ status: Int, _ message: String) -> AgentHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: ["error": message], options: [.sortedKeys])) ?? Data()
        return AgentHTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    static func png(_ data: Data) -> AgentHTTPResponse {
        AgentHTTPResponse(status: 200, contentType: "image/png", body: data)
    }

    /// The response as it goes on the wire. `Connection: close`: the door answers one request per connection.
    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}

/// Who may ask. The listener is bound to the loopback address, so only this Mac reaches it; this decides which process on this Mac.
nonisolated enum AgentDoorGate {
    /// The refusal for `request`, or nil when it may pass.
    ///
    /// - A request with an `Origin` header comes from a web page in a browser; the door is not for pages, with or without the token.
    /// - `Host` must name this Mac's loopback address and the door's port: a page that reached the port through a DNS name it
    ///   controls (DNS rebinding) carries that name here.
    /// - The token is the app's (Settings > Agents > Copy Connection Command), kept in its own preferences.
    static func refusal(for request: AgentHTTPRequest, token: String, port: UInt16) -> AgentHTTPResponse? {
        if request.headers["origin"] != nil { return .error(403, "Requests from web pages are refused.") }
        let host = request.headers["host"] ?? ""
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else { return .error(403, "The Host header does not name this door.") }
        guard !token.isEmpty, let sent = bearerToken(request.headers["authorization"]), sameBytes(sent, token) else {
            return .error(401, "Missing or wrong token. Copy the connection command again in the app's Settings > Agents.")
        }
        return nil
    }

    static func bearerToken(_ header: String?) -> String? {
        guard let header, header.lowercased().hasPrefix("bearer ") else { return nil }
        return String(header.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
    }

    /// Equal, in time that depends on the lengths only.
    static func sameBytes(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<x.count { difference |= x[i] ^ y[i] }
        return difference == 0
    }
}
