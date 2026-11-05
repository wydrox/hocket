enum MessageStatus: String, Codable, Sendable, Equatable {
    case complete, streaming, pending, failed
}
