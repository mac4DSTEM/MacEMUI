//
//  AgentDoorServer.swift
//  Role: The agent door's listener (`AgentDoor.swift`): a TCP listener on this Mac's loopback address, a port the system picks,
//        one HTTP request per connection (`AgentHTTP.swift`). Network.framework, no third-party server.
//
//  Everything runs on the main queue: the listener, each connection, the handler. The handler reads a window's state, which is
//  the main actor's, and the traffic is one agent asking a few questions, so there is nothing to win by leaving it and one
//  whole class of mistakes to lose. Network's callbacks are `@Sendable` closures; each steps back onto the main actor with
//  `MainActor.assumeIsolated`, which is true because the queue they were given is the main one.
//
//  Bound to 127.0.0.1 and `acceptLocalOnly`: no other machine reaches it. The sandbox needs
//  `com.apple.security.network.server` for any listener, this one included.
//

import Foundation
import Network

/// Steps onto the main actor from a callback Network or Dispatch delivers on the main queue.
nonisolated func onMainQueue(_ body: @MainActor () -> Void) {
    MainActor.assumeIsolated { body() }
}

final class AgentDoorServer {
    enum State: Equatable {
        case stopped
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    /// More than this many connections at once are turned away (one agent asks one question at a time).
    static let maximumConnections = 16

    private(set) var state: State = .stopped
    var onStateChange: ((State) -> Void)?

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: AgentDoorConnection] = [:]
    private let handler: (AgentHTTPRequest) -> AgentHTTPResponse

    /// `handler` answers one request; it is called on the main actor.
    init(handler: @escaping (AgentHTTPRequest) -> AgentHTTPResponse) {
        self.handler = handler
    }

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host.ipv4(IPv4Address.loopback), port: NWEndpoint.Port.any)
        parameters.acceptLocalOnly = true
        do {
            let made = try NWListener(using: parameters)
            made.stateUpdateHandler = { [weak self] new in
                onMainQueue { self?.listenerChanged(new) }
            }
            made.newConnectionHandler = { [weak self] connection in
                onMainQueue { self?.accept(connection) }
            }
            listener = made
            set(.starting)
            made.start(queue: .main)
        } catch {
            set(.failed(error.localizedDescription))
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for connection in Array(connections.values) { connection.close() }
        connections.removeAll()
        set(.stopped)
    }

    private func set(_ new: State) {
        guard new != state else { return }
        state = new
        onStateChange?(new)
    }

    private func listenerChanged(_ new: NWListener.State) {
        switch new {
        case .ready:
            if let port = listener?.port?.rawValue { set(.listening(port: port)) }
        case .failed(let error):
            listener?.cancel()
            listener = nil
            set(.failed(error.localizedDescription))
        case .waiting(let error):
            set(.failed(error.localizedDescription))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maximumConnections else { connection.cancel(); return }
        let handled = AgentDoorConnection(connection, respond: handler) { [weak self] closed in
            self?.connections[ObjectIdentifier(closed)] = nil
        }
        connections[ObjectIdentifier(handled)] = handled
        handled.start()
    }
}

/// One connection: read one request, answer it, close. Closed by itself after `timeout` whatever happened.
final class AgentDoorConnection {
    static let timeout: TimeInterval = 20

    private let connection: NWConnection
    private let respond: (AgentHTTPRequest) -> AgentHTTPResponse
    private let onClose: (AgentDoorConnection) -> Void
    private var buffer = Data()
    private var answered = false
    private var closed = false

    init(_ connection: NWConnection, respond: @escaping (AgentHTTPRequest) -> AgentHTTPResponse,
         onClose: @escaping (AgentDoorConnection) -> Void) {
        self.connection = connection
        self.respond = respond
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] new in
            onMainQueue { self?.connectionChanged(new) }
        }
        connection.start(queue: .main)
        receive()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            onMainQueue { self?.close() }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose(self)
    }

    private func connectionChanged(_ new: NWConnection.State) {
        switch new {
        case .failed, .cancelled: close()
        default: break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            let failed = error != nil
            onMainQueue { self?.received(data, isComplete: isComplete, failed: failed) }
        }
    }

    private func received(_ data: Data?, isComplete: Bool, failed: Bool) {
        guard !closed, !answered else { return }
        if let data { buffer.append(data) }
        switch AgentHTTP.parse(buffer) {
        case .incomplete:
            if isComplete || failed { close() } else { receive() }
        case .malformed(let why):
            send(.error(400, why))
        case .request(let request):
            send(respond(request))
        }
    }

    private func send(_ response: AgentHTTPResponse) {
        answered = true
        connection.send(content: response.serialized(), completion: .contentProcessed { [weak self] _ in
            onMainQueue { self?.close() }
        })
    }
}
