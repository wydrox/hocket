import Foundation
import Testing
@testable import HermesPocket

struct StoredTranscriptClientTests {
    private func page(_ rows: [JSONValue], profile: String = "alpha", offset: Int = 0, limit: Int = 5,
                      overrides: [String: JSONValue] = [:], pagination: [String: JSONValue] = [:]) -> JSONValue {
        .object(["session_id": .string("tip"), "profile": .string(profile), "messages": .array(rows),
            "pagination": .object(["limit": .integer(Int64(limit)), "offset": .integer(Int64(offset)),
                "order": .string("latest"), "returned": .integer(Int64(rows.count))].merging(pagination) { _, new in new })]
            .merging(overrides) { _, new in new })
    }

    @Test func requestUsesExplicitProfileAndAuthenticatedBoundedLatestPage() throws {
        let credentials = GatewayCredentials(endpoint: "https://example.test", token: "dummy-test-token", profileName: "other")
        let request = try StoredTranscriptClient.request(credentials: credentials, sessionID: "root/../tip?profile=other#%", profile: "alpha & beta", offset: 500)
        let url = try #require(request.url)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.percentEncodedPath == "/api/sessions/root%2F%2E%2E%2Ftip%3Fprofile%3Dother%23%25/messages")
        #expect(parts.fragment == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dummy-test-token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.timeoutInterval == 30)
        #expect(!request.httpShouldHandleCookies)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(parts.queryItems == [URLQueryItem(name: "profile", value: "alpha & beta"),
            URLQueryItem(name: "limit", value: "500"), URLQueryItem(name: "offset", value: "500"),
            URLQueryItem(name: "order", value: "latest"), URLQueryItem(name: "include_compacted", value: "true"),
            URLQueryItem(name: "inline_images", value: "false")])
    }

    @Test func requestRejectsMissingScopeAndInvalidBounds() {
        let credentials = GatewayCredentials(endpoint: "https://example.test", token: "dummy")
        for (id, profile, offset, limit) in [("", "alpha", 0, 500), ("tip", " ", 0, 500),
            ("tip", "alpha", -1, 500), ("tip", "alpha", 0, 0), ("tip", "alpha", 0, 501)] {
            #expect(throws: (any Error).self) {
                try StoredTranscriptClient.request(credentials: credentials, sessionID: id, profile: profile, offset: offset, limit: limit)
            }
        }
    }

    @Test func projectsDisplayRowsAndKeepsRawPaginationAcrossPhysicalAncestors() throws {
        let rows: [JSONValue] = [
            .object(["id": .integer(11), "session_id": .string("old"), "role": .string("user"), "content": .string("Original")]),
            .object(["id": .integer(12), "role": .string("user"), "content": .string("HIDDEN"), "display_kind": .string("hidden")]),
            .object(["id": .integer(13), "role": .string("user"), "content": .string("MERGE"), "display_metadata": .object(["model_only": .bool(true)])]),
            .object(["id": .integer(14), "role": .string("assistant"), "content": .string("INTERNAL"),
                "display_content": .array([.object(["type": .string("text"), "text": .string("Public")])])]),
            .object(["id": .integer(15), "role": .string("tool"), "tool_name": .string("terminal"), "content": .string("tool")])]
        let result = try StoredTranscriptPage(page(rows), expectedProfile: "alpha", expectedOffset: 0)
        #expect(result.sessionID == "tip")
        #expect(result.profile == "alpha")
        #expect(result.messages.map(\.id) == ["11", "14", "15"])
        #expect(result.messages.map(\.text) == ["Original", "Public", "tool"])
        #expect(result.messages.last?.toolName == "terminal")
        #expect(result.rawCount == 5)
        #expect(result.nextOffset == 5)
        #expect(result.hasOlder)
    }

    @Test func explicitEmptyOrNullDisplayContentCannotExposeRawContentOrTextFallback() throws {
        let displayValues: [JSONValue] = [.string(""), .array([]), .null]
        let rows: [JSONValue] = displayValues.enumerated().map { index, display in
            .object(["id": .integer(Int64(index)), "role": .string("assistant"), "content": .string("PRIVATE"),
                "text": .string("ALSO PRIVATE"), "display_content": display])
        }
        let result = try StoredTranscriptPage(page(rows), expectedProfile: "alpha", expectedOffset: 0)
        #expect(result.messages.count == 3)
        #expect(result.messages.allSatisfy { $0.text.isEmpty && $0.attachments.isEmpty })
        #expect(!result.hasOlder)
    }

    @Test func fullyFilteredPagesAdvanceByRawCountAndAnEmptyPageEndsHistory() throws {
        let hidden: JSONValue = .object(["role": .string("user"), "display_kind": .string("hidden")])
        let filtered = try StoredTranscriptPage(page([hidden, hidden], offset: 5, limit: 2), expectedProfile: "alpha", expectedOffset: 5)
        #expect(filtered.messages.isEmpty)
        #expect(filtered.rawCount == 2)
        #expect(filtered.nextOffset == 7)
        #expect(filtered.hasOlder)
        let empty = try StoredTranscriptPage(page([], offset: 7), expectedProfile: "alpha", expectedOffset: 7)
        #expect(empty.nextOffset == 7)
        #expect(!empty.hasOlder)
    }

    @Test func malformedOrWrongScopePagesFailClosed() {
        let row: JSONValue = .object(["role": .string("user"), "content": .string("Public")])
        let invalid: [JSONValue] = [
            page([], profile: "other"), page([], offset: 1), page([], limit: 0), page([], limit: 501),
            page([], overrides: ["session_id": .string("")]), page([], overrides: ["messages": .null]),
            page([], pagination: ["order": .string("oldest")]), page([], pagination: ["returned": .integer(1)]),
            page([], pagination: ["offset": .number(0)]), page([.null]),
            page([row, row], limit: 1),
            page([.object(["role": .string("assistant"), "display_content": .bool(false)])])]
        for value in invalid {
            #expect(throws: (any Error).self) { try StoredTranscriptPage(value, expectedProfile: "alpha", expectedOffset: 0) }
        }
        #expect(throws: (any Error).self) {
            try StoredTranscriptPage(page([row], offset: Int.max), expectedProfile: "alpha", expectedOffset: Int.max)
        }
        #expect(throws: (any Error).self) { try StoredTranscriptPage(page([]), expectedProfile: "", expectedOffset: 0) }
    }
}
