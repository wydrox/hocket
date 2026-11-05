import Foundation

struct GatewayCredentials: Codable, Sendable, Equatable {
    var endpoint: String
    var token: String
    var refreshToken: String?
    var provider: String?
    var expiresAt: Date?
    var accountID: String?
    /// This client's routing preference, never the server's global default.
    var profileName: String?
}
