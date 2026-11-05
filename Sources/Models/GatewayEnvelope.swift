import Foundation

struct GatewayEnvelope: Codable, Sendable, Equatable {
    var jsonrpc = "2.0"
    var id: JSONValue?
    var method: String?
    var params: JSONValue?
    var result: JSONValue?
    var error: GatewayRPCError?

    static func decodeFrames(_ data: Data) throws -> [GatewayEnvelope] {
        guard let text = String(data: data, encoding: .utf8) else { throw GatewayError.invalidFrame }
        return try text.split(whereSeparator: \.isNewline).map {
            try JSONDecoder().decode(Self.self, from: Data($0.utf8))
        }
    }
}
