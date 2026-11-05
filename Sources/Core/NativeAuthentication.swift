import CryptoKit
import Foundation
import Security

struct NativeAuthentication {
    static let callback = "http://127.0.0.1:53999/cb"

    func accountIdentity(_ credentials: GatewayCredentials) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: try GatewayEndpoint(credentials.endpoint).httpURL(path: "api/auth/me"))
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidFrame }
        guard response.statusCode == 200 else { throw GatewayError.authentication(response.statusCode) }
        let identity = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let user = identity["user_id"].string, !user.isEmpty, let provider = identity["provider"].string else {
            throw GatewayError.invalidResponse("Hermes did not identify the signed-in account.")
        }
        let identityData = try JSONEncoder().encode([provider, user])
        return Self.base64URL(Data(SHA256.hash(data: identityData)))
    }

    func signIn(endpoint: GatewayEndpoint, username: String, password: String) async throws -> GatewayCredentials {
        guard !username.isEmpty, !password.isEmpty else { throw GatewayError.invalidResponse("Enter your Hermes username and password.") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let providers = try await json(session, url: endpoint.httpURL(path: "api/auth/providers"))
        guard (providers["providers"].array ?? []).contains(where: { ($0["name"].string == "basic" || $0["id"].string == "basic") && $0["supports_password"].bool == true }) else {
            throw GatewayError.invalidResponse("This server does not advertise basic password sign-in. Use a supported access token in Advanced connection settings.")
        }
        let verifier = try Self.randomToken()
        let state = try Self.randomToken()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        guard var authorize = URLComponents(url: endpoint.httpURL(path: "auth/native/authorize"), resolvingAgainstBaseURL: false) else { throw GatewayError.invalidEndpoint }
        authorize.queryItems = [URLQueryItem(name: "provider", value: "basic"), URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "redirect_uri", value: Self.callback), URLQueryItem(name: "state", value: state)]
        guard let authorizeURL = authorize.url else { throw GatewayError.invalidEndpoint }
        let (_, response) = try await session.data(from: authorizeURL)
        guard let response = response as? HTTPURLResponse, response.statusCode == 302 else { throw GatewayError.invalidResponse("Hermes could not start native password sign-in.") }
        let login = try await json(session, url: endpoint.httpURL(path: "auth/password-login"), body: ["provider": .string("basic"), "username": .string(username), "password": .string(password)])
        guard login["ok"].bool == true, let next = login["next"].string else { throw GatewayError.invalidResponse("Hermes did not complete native sign-in.") }
        let code = try Self.callbackCode(next, expectedState: state)
        let token = try await json(session, url: endpoint.httpURL(path: "auth/native/token"), body: ["code": .string(code), "code_verifier": .string(verifier)])
        return try Self.credentials(token, endpoint: endpoint)
    }

    func refresh(_ credentials: GatewayCredentials) async throws -> GatewayCredentials {
        guard let refresh = credentials.refreshToken, let provider = credentials.provider else { throw GatewayError.authentication(401) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let endpoint = try GatewayEndpoint(credentials.endpoint)
        let result = try await json(session, url: endpoint.httpURL(path: "auth/native/refresh"), body: ["refresh_token": .string(refresh), "provider": .string(provider)])
        return try Self.credentials(result, endpoint: endpoint)
    }

    static func callbackCode(_ value: String, expectedState: String) throws -> String {
        guard let parts = URLComponents(string: value), parts.scheme == "http", parts.host == "127.0.0.1", parts.port == 53999,
              parts.path == "/cb", parts.user == nil, parts.password == nil, parts.fragment == nil else {
            throw GatewayError.invalidResponse("Hermes returned an unexpected native sign-in callback.")
        }
        let states = parts.queryItems?.filter { $0.name == "state" } ?? []
        let codes = parts.queryItems?.filter { $0.name == "code" } ?? []
        guard states.count == 1, states.first?.value == expectedState, codes.count == 1, let code = codes.first?.value, !code.isEmpty else {
            throw GatewayError.invalidResponse("Native sign-in state verification failed. Start sign-in again.")
        }
        return code
    }

    private func json(_ session: URLSession, url: URL, body: [String: JSONValue]? = nil) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidFrame }
        guard response.statusCode == 200 else { throw GatewayError.authentication(response.statusCode) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func credentials(_ token: JSONValue, endpoint: GatewayEndpoint) throws -> GatewayCredentials {
        guard let access = token["access_token"].string, !access.isEmpty, token["token_type"].string?.lowercased() == "bearer" else {
            throw GatewayError.invalidResponse("Hermes did not return a native bearer credential.")
        }
        return GatewayCredentials(endpoint: endpoint.origin.absoluteString, token: access,
            refreshToken: token["refresh_token"].string, provider: token["provider"].string,
            expiresAt: HermesStore.date(token["expires_at"]))
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw GatewayError.storage("Secure sign-in randomness is unavailable.") }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
    }
}
