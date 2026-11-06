import Foundation

struct StoredTranscriptClient {
    static func request(credentials: GatewayCredentials, sessionID: String, profile: String, offset: Int, limit: Int = 500) throws -> URLRequest {
        guard !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              offset >= 0, (1...500).contains(limit) else {
            throw GatewayError.invalidResponse("Choose a conversation and its named Hermes profile before loading stored messages.")
        }
        guard !credentials.token.isEmpty else { throw GatewayError.emptyToken }
        // Encode the entire identifier as one segment, including dots and literal percent signs.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~")
        guard let encodedID = sessionID.addingPercentEncoding(withAllowedCharacters: allowed),
              var parts = URLComponents(url: try GatewayEndpoint(credentials.endpoint).httpURL(path: "api/sessions"), resolvingAgainstBaseURL: false) else {
            throw GatewayError.invalidEndpoint
        }
        parts.percentEncodedPath += "/\(encodedID)/messages"
        parts.queryItems = [URLQueryItem(name: "profile", value: profile),
            URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "order", value: "latest"), URLQueryItem(name: "include_compacted", value: "true"),
            URLQueryItem(name: "inline_images", value: "false")]
        guard let url = parts.url else { throw GatewayError.invalidEndpoint }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func load(credentials: GatewayCredentials, sessionID: String, profile: String, offset: Int = 0) async throws -> StoredTranscriptPage {
        let request = try Self.request(credentials: credentials, sessionID: sessionID, profile: profile, offset: offset)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidFrame }
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 { throw GatewayError.authentication(response.statusCode) }
            throw GatewayError.invalidResponse("Hermes could not load stored conversation messages (HTTP \(response.statusCode)). Try again.")
        }
        let result = try JSONDecoder().decode(JSONValue.self, from: data)
        return try StoredTranscriptPage(result, expectedProfile: profile, expectedOffset: offset)
    }
}
