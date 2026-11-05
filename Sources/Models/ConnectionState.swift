enum ConnectionState: String, Codable, Sendable, Equatable {
    case disconnected, connecting, connected, reconnecting
}
