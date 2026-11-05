import Foundation

struct GatewayEndpoint: Codable, Sendable, Equatable {
    let origin: URL

    init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              let url = parts.url else { throw GatewayError.invalidEndpoint }
        origin = url
    }

    func httpURL(path: String) -> URL { origin.appending(path: path) }

    func webSocketURL(ticket: String) throws -> URL {
        guard var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { throw GatewayError.invalidEndpoint }
        parts.scheme = "wss"
        parts.path = "/api/ws"
        parts.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        guard let url = parts.url else { throw GatewayError.invalidEndpoint }
        return url
    }
}
