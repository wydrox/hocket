import Foundation
import Testing
@testable import HermesPocket

struct ConnectionSecurityTests {
    @Test(arguments: ["http://hermes.example", "wss://hermes.example", "https://user:pass@hermes.example", "https://hermes.example?token=secret", "https://hermes.example/#secret", "https://hermes.example/api", "https://"])
    func rejectsUnsafeEndpoints(_ input: String) {
        #expect(throws: (any Error).self) { try GatewayEndpoint(input) }
    }

    @Test func usesOnlyOneUseTicketInWebSocketURL() throws {
        let endpoint = try GatewayEndpoint("https://hermes.example:8443/")
        let url = try endpoint.webSocketURL(ticket: "one-use+/=")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "wss")
        #expect(parts.path == "/api/ws")
        #expect(parts.port == 8443)
        #expect(parts.queryItems == [URLQueryItem(name: "ticket", value: "one-use+/=")])
    }

    @Test func nativeCallbackIsParsedLocallyWithExactState() throws {
        #expect(try NativeAuthentication.callbackCode("http://127.0.0.1:53999/cb?code=one-use&state=expected", expectedState: "expected") == "one-use")
    }

    @Test(arguments: [
        "https://attacker.example/cb?code=a&state=expected",
        "http://127.0.0.1:53998/cb?code=a&state=expected",
        "http://127.0.0.1:53999/cb?code=a&state=wrong",
        "http://127.0.0.1:53999/cb?code=a&state=expected&state=expected",
        "http://user@127.0.0.1:53999/cb?code=a&state=expected",
        "http://127.0.0.1:53999/cb?code=a&code=b&state=expected"
    ])
    func rejectsForgedOrAmbiguousCallbacks(_ input: String) {
        #expect(throws: (any Error).self) { try NativeAuthentication.callbackCode(input, expectedState: "expected") }
    }
}
