import Foundation

enum GatewayError: Error, LocalizedError {
    case invalidEndpoint, emptyToken, invalidFrame, disconnected, timeout, unsupportedAuthority, missingSession, invalidResponse(String), storage(String), authentication(Int)
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter an HTTPS origin without a path, credentials, query, or fragment."
        case .emptyToken: "Enter your Hermes access token."
        case .invalidFrame: "Hermes sent an invalid gateway frame."
        case .disconnected: "The Hermes connection was interrupted. Reconnect before continuing."
        case .timeout: "Hermes did not acknowledge the request in time. Retry the original message to preserve its submission identity."
        case .unsupportedAuthority: "This server does not offer the canonical Hermes session gateway."
        case .missingSession: "Open or create a conversation first."
        case .invalidResponse(let message), .storage(let message): message
        case .authentication(let status): "Hermes sign-in failed (HTTP \(status)). Check the endpoint and access token."
        }
    }
}
