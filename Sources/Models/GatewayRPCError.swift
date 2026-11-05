import Foundation

struct GatewayRPCError: Error, Codable, Sendable, Equatable, LocalizedError {
    var code: Int
    var message: String
    var data: JSONValue?
    var errorDescription: String? { message }
}
