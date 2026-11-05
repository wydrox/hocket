import Foundation
import Testing
@testable import HermesPocket

struct ThreadListTests {
    private func response(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test @MainActor func openCanonicalAndStoredHistoryAreMergedBeforeSubstringSearch() async throws {
        let store = HermesStore()
        let stored = try response(#"{"scope":"stored","sessions":[{"id":"history","session_id":"tip","title":"Résumé history","source":"cli","started_at":100.5,"message_count":8,"running":false},{"id":"same","session_id":"same","title":"Stale title","started_at":100,"message_count":1,"running":false}]}"#)
        let live = try response(#"{"scope":"live","sessions":[{"id":"same","session_id":"same","title":"Current résumé","source":"gui","started_at":200,"message_count":3,"running":true},{"id":"new","session_id":"new","title":"New thread","started_at":300,"message_count":0,"running":false}]}"#)
        var requestedScopes: [String] = []
        try await store.loadThreads(query: "SUME") { scope in
            requestedScopes.append(scope)
            return scope == "stored" ? stored : live
        }
        #expect(requestedScopes == ["stored", "live"])
        #expect(store.threads.map(\.id) == ["same", "tip"])
        #expect(store.threads.first?.title == "Current résumé")
        #expect(store.threads.first?.isRunning == true)
        #expect(store.threads.first?.messageCount == 3)
        #expect(store.hasLoadedThreads)
        #expect(store.threadListError == nil)
        #expect(store.threadSearchQuery == "SUME")
    }

    @Test func previewSearchAndEqualDatesHaveStableOrder() {
        let rows = [HermesThread(id: "b", title: "Second", preview: "Find this phrase"), HermesThread(id: "a", title: "First", preview: "FIND THIS PHRASE")]
        #expect(HermesStore.mergeThreads(stored: rows, live: [], query: "this phrase").map(\.id) == ["a", "b"])
    }

    @Test @MainActor func malformedOrFailedFeedPreservesPreviousListAndDoesNotClaimEmptySuccess() async throws {
        let store = HermesStore()
        store.threads = [HermesThread(id: "existing", title: "Existing thread")]
        let stored = try response(#"{"scope":"stored","sessions":[]}"#)
        for invalid in [JSONValue.object([:]), try response(#"{"scope":"live","sessions":null}"#), try response(#"{"scope":"live","sessions":[{"title":"Missing identity"}]}"#)] {
            do {
                try await store.loadThreads(query: "") { $0 == "stored" ? stored : invalid }
                Issue.record("An invalid live response must fail the load")
            } catch {
                #expect(store.threads.map(\.id) == ["existing"])
                #expect(store.threadListError != nil)
                #expect(!store.hasLoadedThreads)
                #expect(!store.isLoadingThreads)
                #expect(store.lastError == nil)
            }
        }
        do {
            try await store.loadThreads(query: "") { _ in throw GatewayError.timeout }
            Issue.record("An unavailable feed must fail the load")
        } catch {
            #expect(store.threads.map(\.id) == ["existing"])
            #expect(store.threadListError != nil)
        }
    }

    @Test @MainActor func staleFailureCannotReplaceNewerSuccessOrItsLoadingState() async throws {
        let store = HermesStore()
        let fresh = try response(#"{"scope":"live","sessions":[{"id":"fresh","session_id":"fresh","title":"Fresh"}]}"#)
        let empty = try response(#"{"scope":"stored","sessions":[]}"#)
        try await store.loadThreads(query: "old") { _ in
            try await store.loadThreads(query: "Fresh") { $0 == "stored" ? empty : fresh }
            throw GatewayError.timeout
        }
        #expect(store.threads.map(\.id) == ["fresh"])
        #expect(store.threadSearchQuery == "Fresh")
        #expect(store.threadListError == nil)
        #expect(!store.isLoadingThreads)
    }

    @Test @MainActor func staleSuccessCannotReplaceNewerSearchResults() async throws {
        let store = HermesStore()
        let empty = try response(#"{"scope":"stored","sessions":[]}"#)
        let fresh = try response(#"{"scope":"live","sessions":[{"id":"fresh","session_id":"fresh","title":"Fresh"}]}"#)
        var obsoleteScopes: [String] = []
        try await store.loadThreads(query: "obsolete") { scope in
            obsoleteScopes.append(scope)
            try await store.loadThreads(query: "Fresh") { $0 == "stored" ? empty : fresh }
            return empty
        }
        #expect(obsoleteScopes == ["stored"])
        #expect(store.threads.map(\.id) == ["fresh"])
        #expect(store.threadSearchQuery == "Fresh")
        #expect(store.threadListError == nil)
    }

    @Test @MainActor func genuineEmptyListsClearPreviousRowsAndCompleteTheLoad() async throws {
        let store = HermesStore()
        store.threads = [HermesThread(id: "removed", title: "Removed")]
        try await store.loadThreads(query: "") { scope in
            .object(["scope": .string(scope), "sessions": .array([])])
        }
        #expect(store.threads.isEmpty)
        #expect(store.hasLoadedThreads)
        #expect(!store.isLoadingThreads)
        #expect(store.threadListError == nil)
    }

    @Test @MainActor func cancelledSearchDoesNotAuthorizeAnEmptyStateForItsQuery() async throws {
        let store = HermesStore()
        store.hasLoadedThreads = true
        store.threadSearchQuery = "old"
        do {
            try await store.loadThreads(query: "new") { _ in throw CancellationError() }
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
        #expect(!store.hasLoadedThreads)
        #expect(!store.isLoadingThreads)
        #expect(store.threadListError == nil)
    }

    @Test @MainActor func createdSnapshotKeepsItsTitleAndThreadWhenRefreshFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HermesStore(draftJournal: DraftJournal(directory: directory))
        let snapshot = try response(#"{"session_id":"created","messages":[],"message_count":0,"running":false,"info":{"desktop_protocol":"hermes-gateway-v1","title":"Server title","started_at":123}}"#)
        try store.installSnapshot(snapshot)
        do {
            try await store.loadThreads(query: "") { _ in throw GatewayError.timeout }
        } catch { }
        #expect(store.selectedThreadID == "created")
        #expect(store.threads.first?.id == "created")
        #expect(store.threads.first?.title == "Server title")
        #expect(store.threadListError != nil)
    }

    @Test @MainActor func catalogCollisionIsAnAdvisoryAndDoesNotBecomeThreadOrChatFailure() throws {
        let store = HermesStore()
        store.lastError = "A separate chat error"
        store.threadListError = "A separate thread error"
        let warning = "slash command /plan unavailable — name taken by built-in; use /skill plan"
        let catalog = try response(#"{"pairs":[["/plan","Plan a task"],["/skill","Run a skill"]],"categories":[],"warning":"slash command /plan unavailable — name taken by built-in; use /skill plan"}"#)
        store.installCommandCatalog(catalog)
        #expect(store.commands.map(\.name) == ["/plan", "/skill"])
        #expect(store.commandWarning == warning)
        #expect(store.lastError == "A separate chat error")
        #expect(store.threadListError == "A separate thread error")
        store.installCommandCatalog(try response(#"{"pairs":[],"warning":""}"#))
        #expect(store.commandWarning == nil)
    }

    @Test @MainActor func catalogConnectionErrorsRemainInTheirOwnSurfaces() async {
        let store = HermesStore()
        await store.loadCatalogs()
        #expect(store.commandCatalogError != nil)
        #expect(store.modelCatalogError != nil)
        #expect(store.threadListError == nil)
        #expect(store.lastError == nil)
    }
}
