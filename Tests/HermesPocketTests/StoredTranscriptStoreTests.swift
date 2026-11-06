import Foundation
import Testing
@testable import HermesPocket

struct StoredTranscriptStoreTests {
    private var notFound: GatewayRPCError {
        GatewayRPCError(code: 4001, message: "not_found", data: .object(["reason": .string("not_found")]))
    }

    @MainActor private func listedStore() -> HermesStore {
        let store = HermesStore()
        store.credentials = GatewayCredentials(endpoint: "https://example.test", token: "dummy", profileName: "alpha")
        store.accountID = "account"
        store.profileID = "/profiles/alpha"
        store.selectedProfileName = "alpha"
        store.connection = .connected
        let thread = HermesThread(id: "legacy", title: "Previous conversation", preview: "Saved reply", updatedAt: nil, messageCount: 5, isRunning: false)
        store.threadHistory.scope = store.currentHistoryScope
        store.threadHistory.rows = [HistoryThreadRow(thread: thread)]
        store.threads = [thread]
        return store
    }

    private func page(_ rows: [JSONValue], offset: Int = 0, limit: Int = 500, profile: String = "alpha") throws -> StoredTranscriptPage {
        try StoredTranscriptPage(.object(["session_id": .string("physical-descendant"), "profile": .string(profile),
            "messages": .array(rows), "pagination": .object(["limit": .integer(Int64(limit)),
                "offset": .integer(Int64(offset)), "order": .string("latest"), "returned": .integer(Int64(rows.count))])]),
            expectedProfile: profile, expectedOffset: offset)
    }

    private func row(_ id: Int64, _ text: String, hidden: Bool = false) -> JSONValue {
        var data: [String: JSONValue] = ["id": .integer(id), "role": .string("assistant"), "content": .string(text)]
        if hidden { data["display_kind"] = .string("hidden") }
        return .object(data)
    }

    private func snapshot(_ id: String) -> JSONValue {
        .object(["session_id": .string(id), "messages": .array([row(99, "Live conversation")]),
            "subscription_id": .string("subscription"), "replay_epoch": .string("epoch"), "last_sequence": .integer(7),
            "revision": .integer(2), "execution_generation": .integer(3),
            "info": .object(["desktop_protocol": .string("hermes-gateway-v1"), "title": .string("Live")])])
    }

    @Test @MainActor func listedLegacyRefusalLoadsNamedProfileHistoryWithoutCanonicalIdentity() async throws {
        let store = listedStore()
        var methods: [String] = []
        var requestedProfiles: [String] = []
        await store.openThread("legacy", rpc: { method, _ in methods.append(method); throw notFound },
            fetchStoredTranscript: { id, profile, offset in
                #expect(store.openingThreadID == "legacy")
                #expect(store.isLoadingMessages)
                #expect(id == "legacy")
                #expect(offset == 0)
                requestedProfiles.append(profile)
                return try page([row(1, "Saved answer")])
            })
        #expect(methods == ["session.resume"])
        #expect(requestedProfiles == ["alpha"])
        #expect(store.selectedThreadID == "legacy")
        #expect(store.messages.map(\.text) == ["Saved answer"])
        #expect(store.isReadOnlyConversation)
        #expect(store.cursors.isEmpty)
        #expect(store.threadHistory.resumedAliases.isEmpty)
        #expect(!store.supportsAttachments && !store.supportsModelControls && !store.supportsInterrupt)
        #expect(!store.supportsThreadArchive && !store.supportsThreadRename)
        #expect(store.threadOpenErrorID == nil && store.openingThreadID == nil)
        #expect(!store.isLoadingMessages)
    }

    @Test @MainActor func unknownOrDeniedConversationDoesNotUseHistoryFallbackAndCanRetry() async throws {
        for error in [notFound, GatewayRPCError(code: 4001, message: "permission_denied", data: .object(["reason": .string("permission_denied")]))] {
            let store = listedStore()
            var fetched = false
            let id = error.message == "not_found" ? "unlisted" : "legacy"
            await store.openThread(id, rpc: { _, _ in throw error }, fetchStoredTranscript: { _, _, _ in
                fetched = true
                return try page([])
            })
            #expect(!fetched)
            #expect(store.selectedThreadID == nil)
            #expect(store.threadOpenErrorID == id)
            #expect(store.threadOpenError == error.localizedDescription)
            #expect(!store.isLoadingMessages)
            await store.openThread(id, rpc: { _, _ in snapshot(id) })
            #expect(store.selectedThreadID == id)
            #expect(store.messages.first?.text == "Live conversation")
            #expect(store.threadOpenErrorID == nil && store.threadOpenError == nil)
            #expect(!store.isReadOnlyConversation)
        }
    }

    @Test @MainActor func staleProfileHistoryCannotInstallOrClearNewLoadingState() async throws {
        let store = listedStore()
        await store.openThread("legacy", rpc: { _, _ in throw notFound }, fetchStoredTranscript: { _, _, _ in
            store.beginConnectionTransition()
            store.selectedProfileName = "beta"
            store.profileID = "/profiles/beta"
            store.isLoadingMessages = true
            store.openingThreadID = "beta-thread"
            store.messages = [ChatMessage(id: "beta-message", role: .assistant, text: "Beta")]
            return try page([row(1, "Alpha must not appear")])
        })
        #expect(store.messages.map(\.text) == ["Beta"])
        #expect(store.selectedThreadID == nil)
        #expect(!store.isReadOnlyConversation)
        #expect(store.openingThreadID == "beta-thread")
        #expect(store.isLoadingMessages)
        #expect(store.threadOpenError == nil)
    }

    @Test @MainActor func filteredPaginationUsesRawOffsetsAndFailureRetriesWithoutLosingMessages() async throws {
        let store = listedStore()
        await store.openThread("legacy", rpc: { _, _ in throw notFound }, fetchStoredTranscript: { _, _, _ in
            try page([row(3, "Newest"), row(4, "Hidden", hidden: true)], limit: 2)
        })
        #expect(store.messages.map(\.id) == ["3"])
        #expect(store.hasOlderMessages)
        await store.loadOlderMessages { id, profile, offset in
            #expect(id == "legacy" && profile == "alpha" && offset == 2)
            return try page([row(2, "Earlier"), row(3, "Duplicate newest")], offset: offset, limit: 2)
        }
        #expect(store.messages.map(\.text) == ["Earlier", "Newest"])
        #expect(store.storedTranscript?.nextOffset == 4)
        await store.loadOlderMessages { _, _, offset in
            #expect(offset == 4)
            throw GatewayError.timeout
        }
        #expect(store.olderMessagesError != nil)
        #expect(store.messages.map(\.text) == ["Earlier", "Newest"])
        #expect(store.storedTranscript?.nextOffset == 4)
        await store.loadOlderMessages { _, _, offset in
            #expect(offset == 4)
            return try page([row(1, "Oldest")], offset: offset, limit: 2)
        }
        #expect(store.messages.map(\.text) == ["Oldest", "Earlier", "Newest"])
        #expect(!store.hasOlderMessages)
        #expect(store.olderMessagesError == nil)
    }

    @Test @MainActor func readOnlyHistoryRejectsEventsAndWritesThenCanonicalOpenRestoresControls() async throws {
        let store = listedStore()
        await store.openThread("legacy", rpc: { _, _ in throw notFound }, fetchStoredTranscript: { _, _, _ in try page([row(1, "Saved")]) })
        store.applyEvent(.object(["type": .string("message.delta"), "session_id": .string("legacy"),
            "seq": .integer(1), "payload": .object(["text": .string("Unsubscribed delta")])]))
        #expect(store.messages.map(\.text) == ["Saved"])
        #expect(store.cursors.isEmpty)
        store.receiveServerRequest(GatewayEnvelope(id: .string("old-request"), method: "approval", params: .object([
            "session_id": .string("legacy"), "command": .string("must not run"), "choices": .array([.string("allow")])
        ])))
        #expect(store.pendingInteraction == nil && store.interactions.isEmpty)
        #expect(!store.canDownload(.reference("/tmp/saved-file.txt")))
        var mutations = 0
        do {
            _ = try await store.mutate("legacy", operation: "archive", payload: [:], requiresGeneration: false,
                rpc: { _, _ in mutations += 1; return .object([:]) })
            Issue.record("Saved history must not mutate")
        } catch { }
        #expect(mutations == 0)
        store.composerText = "Must not send"
        await store.sendMessage()
        #expect(store.submissions.isEmpty)
        #expect(store.messages.map(\.text) == ["Saved"])
        await store.openThread("live", rpc: { _, _ in snapshot("live") })
        #expect(!store.isReadOnlyConversation)
        #expect(store.storedTranscript == nil)
        #expect(store.messages.map(\.text) == ["Live conversation"])
        #expect(store.cursors["live"]?.subscriptionID == "subscription")
        #expect(store.supportsAttachments)
    }

    @Test @MainActor func lateOlderPageCannotLeakAcrossProfileChange() async throws {
        let store = listedStore()
        await store.openThread("legacy", rpc: { _, _ in throw notFound }, fetchStoredTranscript: { _, _, _ in
            try page([row(1, "Current")], limit: 1)
        })
        await store.loadOlderMessages { _, _, offset in
            store.beginConnectionTransition()
            store.selectedProfileName = "beta"
            store.messages = [ChatMessage(id: "beta", role: .assistant, text: "Beta")]
            store.isLoadingOlderMessages = true
            return try page([row(2, "Old alpha")], offset: offset, limit: 1)
        }
        #expect(store.messages.map(\.text) == ["Beta"])
        #expect(store.storedTranscript == nil)
        #expect(store.isLoadingOlderMessages)
        #expect(store.olderMessagesError == nil)
    }
}
