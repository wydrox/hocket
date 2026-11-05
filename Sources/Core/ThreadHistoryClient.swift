import Foundation

struct ThreadHistoryClient {
    static func request(credentials: GatewayCredentials, offset: Int, limit: Int = 50) throws -> URLRequest {
        guard offset >= 0, (1...100).contains(limit),
              var parts = URLComponents(url: try GatewayEndpoint(credentials.endpoint).httpURL(path: "api/sessions"), resolvingAgainstBaseURL: false) else {
            throw GatewayError.invalidEndpoint
        }
        parts.queryItems = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "order", value: "recent"), URLQueryItem(name: "archived", value: "exclude"),
            URLQueryItem(name: "exclude_sources", value: "kanban,tool,oneshot,subagent")]
        if let profile = credentials.profileName, !profile.isEmpty { parts.queryItems?.append(URLQueryItem(name: "profile", value: profile)) }
        guard let url = parts.url else { throw GatewayError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func load(credentials: GatewayCredentials, offset: Int) async throws -> JSONValue {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let request = try Self.request(credentials: credentials, offset: offset)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidFrame }
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 { throw GatewayError.authentication(response.statusCode) }
            throw GatewayError.invalidResponse("Hermes could not load conversation history (HTTP \(response.statusCode)). Try again.")
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
