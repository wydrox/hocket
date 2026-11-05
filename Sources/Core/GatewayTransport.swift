import Foundation

/// Owns the socket and RPC continuations on one executor. Payloads are Sendable values.
@MainActor
final class GatewayTransport {
    var onEvent: ((JSONValue) -> Void)?
    var onServerRequest: ((GatewayEnvelope) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private var socket: URLSessionWebSocketTask?
    private let session: URLSession
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<JSONValue, any Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var authorityReady: Bool?
    private var generation = UUID()
    private(set) var profileName: String?

    func selectProfile(_ name: String?) { profileName = HermesProfile.normalizedName(name) }

    /// Explicit allowlist: connection-level negotiation must never acquire profile params.
    nonisolated static func parameters(for method: String, params: [String: JSONValue], profileName: String?) -> [String: JSONValue] {
        let scoped: Set<String> = [
            "session.list", "session.create", "session.resume", "session.detach", "session.info", "session.history",
            "session.events.since", "session.mutate", "session.interrupt", "session.stats",
            "prompt.submit", "prompt.receipt", "prompt.cancel", "prompt.resolve_unknown", "prompt.steer_queued", "prompt.replace_queued",
            "commands.catalog", "command.dispatch", "complete.slash", "slash.exec",
            "config.get", "config.set", "model.options", "image.attach_bytes", "file.attach", "approval.respond", "clarify.respond"
        ]
        guard scoped.contains(method), let name = HermesProfile.normalizedName(profileName) else { return params }
        var routed = params
        routed["profile"] = .string(name)
        return routed
    }

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
    }

    func connect(endpoint: GatewayEndpoint, token: String) async throws {
        disconnect()
        let attempt = generation
        var ticketRequest = URLRequest(url: endpoint.httpURL(path: "api/auth/ws-ticket"))
        ticketRequest.httpMethod = "POST"
        ticketRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: ticketRequest)
        guard attempt == generation else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidFrame }
        guard response.statusCode == 200 else { throw GatewayError.authentication(response.statusCode) }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let ticket = value["ticket"].string, !ticket.isEmpty else {
            throw GatewayError.invalidResponse("Hermes did not return a one-use WebSocket ticket.")
        }
        var request = URLRequest(url: try endpoint.webSocketURL(ticket: ticket))
        request.setValue("hermes-gateway-v1", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let webSocket = session.webSocketTask(with: request)
        webSocket.maximumMessageSize = 32 * 1024 * 1024
        socket = webSocket
        webSocket.resume()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await webSocket.receive()
                    guard let self, self.generation == attempt else { return }
                    let bytes: Data
                    switch message {
                    case .data(let data): bytes = data
                    case .string(let text): bytes = Data(text.utf8)
                    @unknown default: throw GatewayError.invalidFrame
                    }
                    for envelope in try GatewayEnvelope.decodeFrames(bytes) { self.receive(envelope) }
                } catch {
                    guard let self, self.generation == attempt, !Task.isCancelled else { return }
                    self.failConnection(error)
                    return
                }
            }
        }
        for _ in 0..<150 {
            try Task.checkCancellation()
            guard attempt == generation, socket != nil else { throw GatewayError.disconnected }
            if let authorityReady {
                guard authorityReady else { throw GatewayError.unsupportedAuthority }
                _ = try await call("client.capabilities", params: ["server_requests": .bool(true)])
                startHeartbeat(attempt: attempt)
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw GatewayError.timeout
    }

    func disconnect() {
        generation = UUID()
        profileName = nil
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        receiveTask = nil
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        authorityReady = nil
        for deadline in deadlines.values { deadline.cancel() }
        deadlines.removeAll()
        let waiting = pending.values
        pending.removeAll()
        for continuation in waiting { continuation.resume(throwing: GatewayError.disconnected) }
    }

    func call(_ method: String, params: [String: JSONValue] = [:], timeout: Duration = .seconds(30)) async throws -> JSONValue {
        guard let socket else { throw GatewayError.disconnected }
        let id = UUID().uuidString
        let frame = GatewayEnvelope(id: .string(id), method: method,
            params: .object(Self.parameters(for: method, params: params, profileName: profileName)))
        let bytes = try JSONEncoder().encode(frame)
        guard let text = String(data: bytes, encoding: .utf8) else { throw GatewayError.invalidFrame }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.finish(id, result: .failure(GatewayError.timeout))
                }
                Task { [weak self] in
                    do {
                        try Task.checkCancellation()
                        try await socket.send(.string(text))
                    } catch { self?.finish(id, result: .failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    func respond(id: JSONValue, result: JSONValue) async throws {
        guard let socket else { throw GatewayError.disconnected }
        let bytes = try JSONEncoder().encode(GatewayEnvelope(id: id, result: result))
        guard let text = String(data: bytes, encoding: .utf8) else { throw GatewayError.invalidFrame }
        try await socket.send(.string(text))
    }

    private func receive(_ envelope: GatewayEnvelope) {
        if let method = envelope.method {
            if method == "event", let event = envelope.params {
                if event["type"].string == "gateway.ready" { authorityReady = event["payload"]["session_authority"].bool == true }
                onEvent?(event)
            } else if envelope.id != nil { onServerRequest?(envelope) }
            return
        }
        guard let id = envelope.id?.identifier else { return }
        if let error = envelope.error { finish(id, result: .failure(error)) }
        else { finish(id, result: .success(envelope.result ?? .null)) }
    }

    private func finish(_ id: String, result: Result<JSONValue, any Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func startHeartbeat(attempt: UUID) {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                    guard let self, self.generation == attempt else { return }
                    _ = try await self.call("gateway.ping", timeout: .seconds(30))
                } catch {
                    guard let self, self.generation == attempt, !Task.isCancelled else { return }
                    self.failConnection(error)
                    return
                }
            }
        }
    }

    private func failConnection(_ error: any Error) {
        disconnect()
        // URLSession descriptions can contain the short-lived ticket URL.
        onDisconnect?(error is GatewayRPCError ? error.localizedDescription : "Connection to Hermes was lost. Reconnecting…")
    }
}
