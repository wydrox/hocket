import Foundation
import Testing
@testable import HermesPocket

struct GatewayPreflightTests {
    @Test func recognizesPasswordProviderAmongOtherProviders() throws {
        let data = Data(#"{"providers":[{"name":"nous"},{"name":"basic","supports_password":true}]}"#.utf8)
        #expect(try GatewayPreflight.signInOptions(data) == .password)
        let alias = Data(#"{"providers":[{"id":"basic","supports_password":true}]}"#.utf8)
        #expect(try GatewayPreflight.signInOptions(alias) == .password)
    }

    @Test(arguments: [
        #"{"providers":[{"name":"nous","supports_password":false}]}"#,
        #"{"providers":[{"name":"basic","supports_password":false}]}"#,
        #"{"providers":[{"name":"basic"}]}"#,
        #"{"providers":[{"name":"other","supports_password":true}]}"#
    ])
    func doesNotOfferUnsupportedPasswordSignIn(_ response: String) throws {
        #expect(try GatewayPreflight.signInOptions(Data(response.utf8)) == .otherProvider)
    }

    @Test func distinguishesMissingSetupFromUnsupportedProvider() throws {
        #expect(try GatewayPreflight.signInOptions(Data(#"{"providers":[]}"#.utf8)) == .notConfigured)
    }

    @Test(arguments: ["<html>Proxy login</html>", "{}", #"{"providers":null}"#, #"{"providers":[{}]}"#])
    func rejectsResponsesFromWrongService(_ response: String) {
        #expect(throws: (any Error).self) { try GatewayPreflight.signInOptions(Data(response.utf8)) }
    }

    @Test func transportErrorsGiveActionableHelpWithoutEchoingURLs() throws {
        let privateURL = try #require(URL(string: "https://private.example/?secret=do-not-display"))
        let error = URLError(.cannotConnectToHost, userInfo: [NSURLErrorFailingURLErrorKey: privateURL])
        let message = GatewayPreflight.message(for: error)
        #expect(message.contains("Tailscale"))
        #expect(!message.contains("private.example"))
        #expect(!message.contains("do-not-display"))
        #expect(GatewayPreflight.message(for: URLError(.serverCertificateUntrusted)).contains("certificate"))
    }
}
