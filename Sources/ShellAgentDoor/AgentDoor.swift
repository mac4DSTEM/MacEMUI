//
//  AgentDoor.swift
//  Role: The agent door both apps share: a local API through which an agent on this Mac (Claude, Codex, a script) looks at what
//        the app's windows show. The app hands it its tools (`AgentTool`); the door owns everything else: the listener on this
//        Mac's loopback address (`AgentDoorServer`), who may ask (`AgentDoorGate`), the file that says where it is, the list of open
//        windows, and the routes.
//
//  Off until the person turns it on (`AgentDoorSettingsSection`, bound to a preference the app keeps). While on, the app listens
//  on 127.0.0.1 only and writes one file, readable by this user's account only: the port and a token made new each time the
//  door opens. The MCP bridge (`macem-mcp`, a separate tool) reads it; a request without the token is refused. Nothing leaves the
//  Mac and the app sends nothing by itself.
//
//  Routes, every one a GET in this version:
//
//    /v1                     the app, the API version, the tools' names
//    /v1/tools               the tools in MCP's shape (name, title, description, input schema, annotations)
//    /v1/tools/<name>        run one: ?window=w1 (or none while one window is open), ?scale=1...3 for a picture
//
//  `list_windows` is the door's own tool: every window enrols with a one-line summary of itself.
//  The sandbox needs `com.apple.security.network.server` for the listener.
//

import Foundation
import Observation

@Observable
public final class AgentDoor {
    /// The API's version: the `/v1` in every path, and `api` in the door's file.
    public static let apiVersion = 1

    public enum Status: Equatable {
        case off
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    public private(set) var status: Status = .off
    /// Requests answered since the door last opened (the Settings row shows it, so the person sees an agent is there).
    public private(set) var requestCount = 0

    /// The app's name: in the door's file, in `/v1`, in the Settings text.
    public let appName: String
    public let appVersion: String
    /// Where the door's file goes; nil writes none (a test that only talks to the port).
    public let discoveryURL: URL?

    @ObservationIgnored private var server: AgentDoorServer?
    @ObservationIgnored private(set) var token = ""
    @ObservationIgnored private var tools: [AgentTool] = []

    private struct Enrolled {
        let id: String
        weak var state: AnyObject?
        let summary: () -> [String: Any]
    }
    @ObservationIgnored private var windows: [Enrolled] = []
    @ObservationIgnored private var nextWindowNumber = 1

    /// The door's file goes to `Application Support/<appName>/agent-door.json` (inside the container for a sandboxed app).
    public convenience init(appName: String, appVersion: String) {
        self.init(appName: appName, appVersion: appVersion, discoveryURL: Self.defaultDiscoveryURL(appName: appName))
    }

    /// `discoveryURL` nil writes no file (a test that talks to the port only).
    public init(appName: String, appVersion: String, discoveryURL: URL?) {
        self.appName = appName
        self.appVersion = appVersion
        self.discoveryURL = discoveryURL
    }

    public static func defaultDiscoveryURL(appName: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("agent-door.json", isDirectory: false)
    }

    // MARK: Tools

    /// The app's tools, in the order an agent should meet them. A name the door already has (its own `list_windows`, or a second
    /// tool of one name) is a programming error.
    public func register(_ added: [AgentTool]) {
        for tool in added {
            precondition(tool.name != Self.listWindowsName && !tools.contains { $0.name == tool.name }, "agent tool \(tool.name) is registered twice")
            tools.append(tool)
        }
    }

    static let listWindowsName = "list_windows"

    /// The door's own tool, then the app's.
    var allTools: [AgentTool] {
        let list = AgentTool(name: Self.listWindowsName, title: "List windows",
                             summary: "The open \(appName) windows, one line each: the id the other tools take, the file, what the window shows.",
                             input: .noWindow) { [weak self] _ in
            .json(["windows": self?.liveWindows.map { $0.summary } ?? []])
        }
        return [list] + tools
    }

    // MARK: Open and close

    /// Opens or closes the door. Asking for the state it already has does nothing, so every window may ask.
    public func setEnabled(_ enabled: Bool) {
        if enabled { open() } else { close() }
    }

    private func open() {
        guard server == nil else { return }
        token = Self.makeToken()
        requestCount = 0
        let made = AgentDoorServer { [weak self] request in
            self?.respond(to: request) ?? .error(503, "The agent door is closed.")
        }
        made.onStateChange = { [weak self] new in self?.serverChanged(new) }
        server = made
        made.start()
    }

    private func close() {
        // Only a door that opened takes the file away: another running copy of the app may own the one that is there.
        guard let running = server else { status = .off; return }
        removeDiscoveryFile()
        running.onStateChange = nil
        server = nil
        running.stop()
        token = ""
        status = .off
    }

    private func serverChanged(_ new: AgentDoorServer.State) {
        switch new {
        case .stopped:
            status = .off
        case .starting:
            status = .starting
        case .listening(let port):
            status = .listening(port: port)
            writeDiscoveryFile(port: port)
        case .failed(let why):
            removeDiscoveryFile()
            server?.onStateChange = nil
            server = nil
            status = .failed(why)
        }
    }

    /// 32 random bytes as hex, from the system's generator.
    nonisolated static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }

    // MARK: The door's file

    /// What the bridge reads: the API version, the port, the token, this process. Written whole, then closed to other accounts.
    private func writeDiscoveryFile(port: UInt16) {
        guard let url = discoveryURL else { return }
        let record: [String: Any] = [
            "api": Self.apiVersion,
            "port": Int(port),
            "token": token,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "app": appName,
            "app_version": appVersion,
        ]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // A door nobody can find is not open: say why instead of listening unseen.
            server?.onStateChange = nil
            server?.stop()
            server = nil
            status = .failed("The door's file could not be written: \(error.localizedDescription)")
        }
    }

    private func removeDiscoveryFile() {
        guard let url = discoveryURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Windows

    /// A window appeared. `summary` is its one line in `list_windows` (the door adds `id`). A second call for the same state keeps
    /// its name.
    public func enroll(_ state: AnyObject, summary: @escaping () -> [String: Any]) {
        windows.removeAll { $0.state == nil }
        guard !windows.contains(where: { $0.state === state }) else { return }
        windows.append(Enrolled(id: "w\(nextWindowNumber)", state: state, summary: summary))
        nextWindowNumber += 1
    }

    /// A window closed.
    public func withdraw(_ state: AnyObject) {
        windows.removeAll { $0.state == nil || $0.state === state }
    }

    /// The open windows, oldest first, each with its summary line.
    var liveWindows: [(window: AgentWindow, summary: [String: Any])] {
        windows.compactMap { enrolled in
            guard let state = enrolled.state else { return nil }
            var line = enrolled.summary()
            line["id"] = enrolled.id
            return (AgentWindow(id: enrolled.id, state: state), line)
        }
    }

    // MARK: Requests

    /// Answers one request: the gate first, then the route.
    func respond(to request: AgentHTTPRequest) -> AgentHTTPResponse {
        guard case .listening(let port) = status else { return .error(503, "The agent door is closed.") }
        if let refusal = AgentDoorGate.refusal(for: request, token: token, port: port) { return refusal }
        requestCount += 1
        return route(request)
    }

    /// Which answer a request gets, the gate passed.
    func route(_ request: AgentHTTPRequest) -> AgentHTTPResponse {
        guard request.method == "GET" else { return .error(405, "This version of the door is read-only: every route is a GET.") }
        let parts = request.path.split(separator: "/").map(String.init)
        let tools = allTools
        switch parts {
        case ["v1"]:
            return .json(["app": appName, "app_version": appVersion, "api": Self.apiVersion, "access": "read-only",
                          "tools": tools.map(\.name)])
        case ["v1", "tools"]:
            return .json(["tools": tools.map(\.descriptor)])
        case let path where path.count == 3 && path[0] == "v1" && path[1] == "tools":
            guard let tool = tools.first(where: { $0.name == path[2] }) else {
                return .error(404, "No tool \(path[2]). GET /v1/tools lists them.")
            }
            return run(tool, query: request.query)
        default:
            return .error(404, "Unknown path. GET /v1 says what this door answers.")
        }
    }

    private func run(_ tool: AgentTool, query: [String: String]) -> AgentHTTPResponse {
        var window: AgentWindow?
        if tool.input != .noWindow {
            switch resolveWindow(query["window"]) {
            case .success(let found): window = found
            case .failure(let refusal): return refusal.response
            }
        }
        let call = AgentToolCall(window: window, scale: Self.scale(query["scale"]), arguments: query)
        switch tool.run(call) {
        case .json(let object): return .json(object)
        case .encodedJSON(let data): return .json(encoded: data)
        case .png(let data): return .png(data)
        case .refusal(let status, let message): return .error(status, message)
        }
    }

    struct Refusal: Error {
        let response: AgentHTTPResponse
    }

    /// The window `id` names; with none (or `current`), the only open window.
    private func resolveWindow(_ id: String?) -> Result<AgentWindow, Refusal> {
        let open = liveWindows
        guard let id, !id.isEmpty, id != "current" else {
            if open.count == 1 { return .success(open[0].window) }
            if open.isEmpty { return .failure(Refusal(response: .error(404, "No \(appName) window is open."))) }
            let names = open.map { "\($0.window.id) (\($0.summary["file_name"] as? String ?? "no file"))" }.joined(separator: ", ")
            return .failure(Refusal(response: .error(409, "Several windows are open; name one: \(names).")))
        }
        guard let found = open.first(where: { $0.window.id == id }) else {
            return .failure(Refusal(response: .error(404, "No window \(id). list_windows lists the open windows.")))
        }
        return .success(found.window)
    }

    /// `scale` 1, 2 or 3; anything else is 1.
    nonisolated static func scale(_ stated: String?) -> Int {
        guard let value = stated.flatMap({ Int($0) }), (1...3).contains(value) else { return 1 }
        return value
    }
}
