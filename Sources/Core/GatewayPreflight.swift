import Foundation

/// Public discovery only. This check never sends credentials or opens a chat.
struct GatewayPreflight {
    enum SignIn: Sendable, Equatable {
        case password
        case otherProvider
        case notConfigured
    }

    func check(_ endpoint: GatewayEndpoint) async throws -> SignIn {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint.httpURL(path: "api/auth/providers"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidFrame }
        guard response.statusCode == 200 else { throw Self.responseError(response.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 65_536 else {
                throw GatewayError.invalidResponse("This address returned an unexpected response. Check that it points to your Hermes gateway.")
            }
            data.append(byte)
        }
        return try Self.signInOptions(data)
    }

    static func signInOptions(_ data: Data) throws -> SignIn {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let providers = value["providers"].array,
              providers.allSatisfy({ $0["name"].string != nil || $0["id"].string != nil }) else {
            throw GatewayError.invalidResponse("This address did not return Hermes sign-in options. Use the gateway’s HTTPS address, without /login or /api.")
        }
        if providers.contains(where: {
            ($0["name"].string == "basic" || $0["id"].string == "basic") && $0["supports_password"].bool == true
        }) {
            return .password
        }
        return providers.isEmpty ? .notConfigured : .otherProvider
    }

    private static func responseError(_ status: Int) -> GatewayError {
        switch status {
        case 300..<400:
            .invalidResponse("This address redirects elsewhere. Enter the final HTTPS address of your Hermes gateway.")
        case 401, 403:
            .invalidResponse("The server blocked the connection check. Check your VPN or proxy access, then try again.")
        case 502, 503, 504:
            .invalidResponse("The address is reachable, but Hermes is unavailable behind it. Check that the gateway is running and the HTTPS proxy points to its current port.")
        default:
            .invalidResponse("This address did not expose Hermes sign-in options (HTTP \(status)). Check the gateway address and try again.")
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Your device is offline. Reconnect to the internet and, for a private server, connect Tailscale or your VPN."
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .timedOut:
                return "Couldn’t reach Hermes. Check the address, keep the server awake, and connect Tailscale or your VPN if the server is private."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return "The server’s HTTPS certificate could not be verified. Check its HTTPS setup before signing in."
            default: break
            }
        }
        if let error = error as? GatewayError { return error.localizedDescription }
        return "Couldn’t check this server. Confirm its HTTPS address and try again."
    }
}
