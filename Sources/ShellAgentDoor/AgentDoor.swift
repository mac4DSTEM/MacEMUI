//
//  AgentDoor.swift
//  Role: The agent door both apps share: a local API through which an agent on this Mac (Claude, Codex, a script) looks at what
//        the app's windows show. The app hands it its tools (`AgentTool`); the door owns everything else: the listener on this
//        Mac's loopback address (`AgentDoorServer`), who may ask (`AgentDoorGate`), the file that says where it is, the list of open
//        windows, and the routes.
//
//  Off until the person turns it on (`AgentDoorSettingsSection`, bound to a preference the app keeps). While on, the app listens
//  on 127.0.0.1 only, on the app's own port (`preferredPort`, another when that one is taken), and answers only requests that
//  carry its token. The token is made once and kept in the app's preferences, so a connection command stays good; the person
//  makes a new one in Settings, which shuts out whoever had the old. An agent gets port and token from the Settings section's
//  Copy Connection Command (`connectionCommand`), which registers the MCP bridge (`macem-mcp`, a separate tool) with them as
//  environment variables. Nothing is written for a helper to find: a sandboxed app's container is closed to other apps, which
//  is why the person hands the bridge the two values, as other sandboxed Mac apps hand out an API key. Nothing leaves the Mac
//  and the app sends nothing by itself.
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
    /// The API's version: the `/v1` in every path, and `api` in `/v1`.
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

    /// The app's name: in `/v1`, in the Settings text, in the connection command.
    public let appName: String
    public let appVersion: String
    /// The port the door asks for first; the system picks another when it is taken (`status` says which).
    public let preferredPort: UInt16
    /// The token a request must carry: 32 random bytes as hex, made once and kept (`defaults`) until `makeNewToken`.
    public private(set) var token: String

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var server: AgentDoorServer?
    @ObservationIgnored private var askedForPreferredPort = false
    @ObservationIgnored private var tools: [AgentTool] = []

    private struct Enrolled {
        let id: String
        weak var state: AnyObject?
        let summary: () -> [String: Any]
    }
    @ObservationIgnored private var windows: [Enrolled] = []
    @ObservationIgnored private var nextWindowNumber = 1

    static let tokenKey = "agentDoor.token"

    /// `defaults` keeps the token (the app's own preferences; a test passes its own suite).
    public init(appName: String, appVersion: String, preferredPort: UInt16, defaults: UserDefaults = .standard) {
        self.appName = appName
        self.appVersion = appVersion
        self.preferredPort = preferredPort
        self.defaults = defaults
        if let kept = defaults.string(forKey: Self.tokenKey), Self.isToken(kept) {
            token = kept
        } else {
            token = Self.makeToken()
            defaults.set(token, forKey: Self.tokenKey)
        }
    }

    /// A new token: whoever had the old one is shut out, and the connection command must be copied again.
    public func makeNewToken() {
        token = Self.makeToken()
        defaults.set(token, forKey: Self.tokenKey)
    }

    nonisolated static func isToken(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy(\.isHexDigit)
    }

    /// What registers the bridge with Claude Code, with this door's port and token; nil while the door is not open.
    /// `bridge` is the bridge's path (`macem-mcp` when it is on the PATH).
    public func connectionCommand(bridge: String = "macem-mcp") -> String? {
        guard case .listening(let port) = status else { return nil }
        let prefix = appName.uppercased() + "_AGENT"
        return "claude mcp add \(appName.lowercased()) -e \(prefix)_PORT=\(port) -e \(prefix)_TOKEN=\(token) -- \(bridge) --app \(appName)"
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
        requestCount = 0
        askedForPreferredPort = true
        listen(on: preferredPort)
    }

    private func listen(on port: UInt16?) {
        let made = AgentDoorServer { [weak self] request in
            self?.respond(to: request) ?? .error(503, "The agent door is closed.")
        }
        made.onStateChange = { [weak self] new in self?.serverChanged(new) }
        server = made
        made.start(port: port)
    }

    private func close() {
        guard let running = server else { status = .off; return }
        running.onStateChange = nil
        server = nil
        running.stop()
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
        case .failed(let why):
            server?.onStateChange = nil
            server?.stop()
            server = nil
            // The app's port is taken (another copy of the app, another program): any free one will do, and the pane says which.
            if askedForPreferredPort {
                askedForPreferredPort = false
                listen(on: nil)
                return
            }
            status = .failed(why)
        }
    }

    /// 32 random bytes as hex, from the system's generator.
    nonisolated static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
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
