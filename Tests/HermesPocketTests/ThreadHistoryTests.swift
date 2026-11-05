import Foundation
import Testing
@testable import HermesPocket

struct ThreadHistoryTests {
    private func row(_ id: String, title: String? = nil, extra: [String: JSONValue] = [:]) -> JSONValue {
        .object(["id": .string(id), "title": .string(title ?? id), "last_active": .integer(500), "source": .string("gui")].merging(extra) { _, new in new })
    }

    private func page(_ rows: [JSONValue], offset: Int = 0, total: Int = 251, limit: Int = 50,
                      storage: [String: JSONValue] = [:]) -> JSONValue {
        .object(["sessions": .array(rows), "offset": .integer(Int64(offset)), "limit": .integer(Int64(limit)),
            "total": .integer(Int64(total)), "storage": .object(storage)])
    }

    private func feed(_ scope: String, _ rows: [JSONValue] = []) -> JSONValue {
        .object(["scope": .string(scope), "sessions": .array(rows)])
    }

    @Test func authenticatedRequestUsesDashboardPaginationAndExplicitNamedProfile() throws {
        var credentials = GatewayCredentials(endpoint: "https://example.test", token: "dummy-test-token")
        let request = try ThreadHistoryClient.request(credentials: credentials, offset: 200)
        let items = try #require(URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        #expect(request.url?.path == "/api/sessions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dummy-test-token")
        #expect(items.contains(URLQueryItem(name: "limit", value: "50")))
        #expect(items.contains(URLQueryItem(name: "offset", value: "200")))
        #expect(items.contains(URLQueryItem(name: "order", value: "recent")))
        #expect(items.contains(URLQueryItem(name: "archived", value: "exclude")))
        #expect(!items.contains { $0.name == "profile" })
        credentials.profileName = "work profile"
        let named = try ThreadHistoryClient.request(credentials: credentials, offset: 0)
        #expect(URLComponents(url: #require(named.url), resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "profile", value: "work profile")) == true)
    }

    @Test @MainActor func olderThanTwoHundredConversationsRemainReachableAndSearchLoadsOlderMatches() async throws {
        let store = HermesStore()
        func fetch(_ offset: Int) async throws -> JSONValue {
            page((offset..<min(offset + 50, 251)).map { row("thread-\($0)") }, offset: offset)
        }
        try await store.loadThreads(query: "thread-250", fetchSessions: { feed($0) }, fetchHistory: fetch)
        #expect(store.threads.isEmpty)
        #expect(store.hasOlderThreads)
        var offsets: [Int] = []
        while store.hasOlderThreads {
            try await store.loadOlderThreads(fetchHistory: { offset in offsets.append(offset); return try await fetch(offset) })
        }
        #expect(offsets == [50, 100, 150, 200, 250])
        #expect(store.threadHistory.rows.count == 251)
        #expect(store.threads.map(\.id) == ["thread-250"])
        #expect(store.threadSearchQuery == "thread-250")
    }

    @Test @MainActor func pinnedOverlapUsesWindowLimitAndCanonicalAuthorityWins() async throws {
        let store = HermesStore()
        let pinned = row("pinned", extra: ["pinned": .bool(true)])
        let physical = row("tip", title: "REST stale", extra: ["source": .string("local"), "chat_id": .string("owner"),
            "_lineage_root_id": .string("root"), "_lineage_ids": .array([.string("root"), .string("tip")])])
        let canonical = row("owner", title: "Canonical", extra: ["session_id": .string("owner"), "running": .bool(true)])
        try await store.loadThreads(query: "", fetchSessions: { feed($0, $0 == "live" ? [canonical] : []) }, fetchHistory: { _ in page([physical, pinned], total: 4, limit: 1) })
        #expect(store.threads.count == 2)
        #expect(store.threads.first { $0.id == "owner" }?.title == "Canonical")
        #expect(store.threads.first { $0.id == "owner" }?.isRunning == true)
        try await store.loadOlderThreads(fetchHistory: { offset in
            #expect(offset == 1)
            return page([pinned], offset: offset, total: 4, limit: 1)
        })
        #expect(store.hasOlderThreads) // A page of previously backfilled pins is not exhaustion.
        try await store.loadOlderThreads(fetchHistory: { offset in
            #expect(offset == 2)
            return page([row("older"), pinned], offset: offset, total: 4, limit: 1)
        })
        #expect(store.threads.count == 3)
        try await store.loadOlderThreads(fetchHistory: { offset in page([], offset: offset, total: 9, limit: 1) })
        #expect(!store.hasOlderThreads) // Hidden rows can inflate the server count.
    }

    @Test @MainActor func failedPageRetainsRowsAndRetriesSameOffset() async throws {
        let store = HermesStore()
        try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("existing")]) })
        do {
            try await store.loadOlderThreads(fetchHistory: { _ in throw GatewayError.timeout })
            Issue.record("Expected pagination failure")
        } catch { }
        #expect(store.threads.map(\.id) == ["existing"])
        #expect(store.threadHistory.nextOffset == 50)
        #expect(store.threadHistoryError != nil)
        #expect(store.threadListError == nil)
        #expect(!store.isLoadingOlderThreads)
        try await store.loadOlderThreads(fetchHistory: { offset in
            #expect(offset == 50)
            return page([row("older")], offset: offset, total: 51)
        })
        #expect(store.threads.count == 2)
        #expect(store.threadHistoryError == nil)
        #expect(!store.hasOlderThreads)
    }

    @Test @MainActor func latePageCannotCrossRefreshOrProfileBoundary() async throws {
        let store = HermesStore()
        try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("old")]) })
        try await store.loadOlderThreads(fetchHistory: { offset in
            try await store.loadThreads(query: "fresh", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("fresh")], total: 1) })
            return page([row("stale")], offset: offset)
        })
        #expect(store.threads.map(\.id) == ["fresh"])
        #expect(!store.isLoadingOlderThreads)
        #expect(!store.hasOlderThreads)
        store.setThreadSearchQuery("")
        store.profileID = "profile-a"
        try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("profile-a")]) })
        try await store.loadOlderThreads(fetchHistory: { offset in
            store.profileID = "profile-b"
            store.resetThreadHistory()
            try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("profile-b")], total: 1) })
            return page([row("cross-profile")], offset: offset)
        })
        #expect(store.threads.map(\.id) == ["profile-b"])
        #expect(store.threadHistory.scope?.profile == "profile-b")
    }

    @Test @MainActor func paginationIsSingleFlightAndAccountChangeDiscardsLateResponse() async throws {
        let store = HermesStore()
        store.credentials = GatewayCredentials(endpoint: "https://first.example.test", token: "dummy")
        store.accountID = "first-account"
        try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("old-account")]) })
        var duplicateFetches = 0
        try await store.loadOlderThreads(fetchHistory: { offset in
            try await store.loadOlderThreads(fetchHistory: { nestedOffset in
                duplicateFetches += 1
                return page([row("duplicate")], offset: nestedOffset)
            })
            store.credentials = GatewayCredentials(endpoint: "https://second.example.test", token: "dummy")
            store.accountID = "second-account"
            store.resetThreadHistory()
            try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("new-account")], total: 1) })
            return page([row("cross-account")], offset: offset)
        })
        #expect(duplicateFetches == 0)
        #expect(store.threads.map(\.id) == ["new-account"])
        #expect(store.threadHistory.scope?.endpoint == "https://second.example.test")
        #expect(store.threadHistory.scope?.account == "second-account")
    }

    @Test @MainActor func corruptOrMalformedRefreshKeepsExistingHistory() async throws {
        let store = HermesStore()
        try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("safe")]) })
        let malformed = [page([], storage: ["default": .string("corrupt")]), page([], offset: 50),
            .object(["sessions": .array([]), "total": .integer(0), "limit": .integer(0), "offset": .integer(0), "storage": .object([:])])]
        for value in malformed {
            do {
                try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in value })
                Issue.record("An invalid history page must fail")
            } catch { }
            #expect(store.threads.map(\.id) == ["safe"])
            #expect(store.threadHistoryError != nil)
            #expect(!store.hasLoadedThreads)
        }
    }

    @Test @MainActor func resumeSnapshotReconcilesPhysicalHistoryIDWithLogicalOwner() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HermesStore(draftJournal: DraftJournal(directory: directory))
        try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("tip")], total: 1) })
        let snapshot: JSONValue = .object(["session_id": .string("owner"), "messages": .array([]), "info": .object([
            "desktop_protocol": .string("hermes-gateway-v1"), "title": .string("Resumed")])])
        try store.installSnapshot(snapshot, requestedID: "tip")
        #expect(store.threads.map(\.id) == ["owner"])
        #expect(store.selectedThreadID == "owner")
        #expect(store.threadHistory.resumedAliases["tip"] == "owner")
    }

    @Test @MainActor func recentActivityAndVisibilityAreUsedAndRefreshRetainsOlderPages() async throws {
        let store = HermesStore()
        try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([
            row("recent", extra: ["last_active": .integer(1000), "started_at": .integer(1)]),
            row("old", extra: ["last_active": .integer(20), "started_at": .integer(900)]),
            row("hidden", extra: ["hidden": .integer(1)]), row("internal", extra: ["source": .string("tool")]),
            row("archived-pin", extra: ["archived": .bool(true), "pinned": .bool(true)]),
            row("archived-int-pin", extra: ["archived": .integer(1), "pinned": .bool(true)])]) })
        #expect(store.threads.map(\.id) == ["recent", "old"])
        try await store.loadOlderThreads(fetchHistory: { offset in page([row("older")], offset: offset, total: 100) })
        store.setThreadSearchQuery("older")
        try await store.loadThreads(query: store.threadSearchQuery, fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("fresh")]) })
        #expect(store.threads.map(\.id) == ["older"])
        #expect(store.threadHistory.nextOffset == 50)
        #expect(store.threadSearchQuery == "older")
        #expect(!store.threadHistory.rows.contains { $0.thread.id == "old" })
    }
    private func snapshot(_ id: String, title: String = "Session", revision: Int64 = 91, generation: Int64 = 8) -> JSONValue {
        .object(["session_id": .string(id), "revision": .integer(revision), "execution_generation": .integer(generation),
            "replay_epoch": .string("epoch"), "last_sequence": .integer(2), "subscription_id": .string("subscription"),
            "messages": .array([]), "info": .object(["desktop_protocol": .string("hermes-gateway-v1"), "title": .string(title)])])
    }

    @MainActor private func switchToOtherProfile(_ store: HermesStore) {
        store.beginConnectionTransition()
        store.profileID = "profile-b"
        store.accountID = "account-b"
        store.lastError = "Profile B error"
        store.isLoadingMessages = true
    }

    @Test @MainActor func canonicalAuthorityPreservesRestActivityAndPreview() async throws {
        let store = HermesStore()
        let stored = row("owner", title: "Canonical title", extra: ["session_id": .string("owner"), "started_at": .integer(1), "last_active": .null])
        let history = row("tip", title: "Older title", extra: ["source": .string("local"), "chat_id": .string("owner"),
            "last_active": .integer(1000), "preview": .string("Preview from history")])
        try await store.loadThreads(query: "", fetchSessions: { feed($0, $0 == "stored" ? [stored] : []) },
            fetchHistory: { _ in page([history, row("other", extra: ["last_active": .integer(500)])], total: 2) })
        #expect(store.threads.map(\.id) == ["owner", "other"])
        #expect(store.threads.first?.title == "Canonical title")
        #expect(store.threads.first?.updatedAt == Date(timeIntervalSince1970: 1000))
        #expect(store.threads.first?.preview == "Preview from history")
    }

    @Test @MainActor func normalizedRenameUpdatesCachedOlderConversationWithoutServerRelistingIt() async throws {
        let store = HermesStore()
        try await store.loadThreads(query: "", fetchSessions: { feed($0) }, fetchHistory: { _ in page([row("recent")]) })
        try await store.loadOlderThreads(fetchHistory: { offset in page([row("old", title: "Old title")], offset: offset) })
        await store.renameThread("old", title: " requested ", rpc: { method, params in
            if method == "session.resume" { return snapshot("old", revision: 7) }
            #expect(method == "session.mutate")
            #expect(params["session_id"] == .string("old"))
            return .object(["session_id": .string("old"), "revision": .integer(8), "title": .string("Normalized title")])
        })
        // The follow-up refresh has no credentials in this fixture, so the cached page must
        // carry the acknowledged normalization independently of any new server list.
        #expect(store.threadHistory.rows.first { $0.thread.id == "old" }?.thread.title == "Normalized title")
        store.setThreadSearchQuery("Normalized")
        #expect(store.threads.map(\.id) == ["old"])
    }

    @Test @MainActor func metadataUsesPhysicalFencesAndPolicyMutationUsesCanonicalOwnerFences() async throws {
        let store = HermesStore()
        var methods: [String] = []
        try await store.mutate("tip", operation: "rename", payload: ["title": .string("New")], requiresGeneration: false,
            rpc: { method, params in
                methods.append(method)
                if method == "session.resume" { return snapshot("owner") }
                #expect(params["session_id"] == .string("tip"))
                #expect(params["expected_revision"] == .integer(7))
                #expect(params["expected_generation"] == nil)
                return .object(["session_id": .string("tip"), "revision": .integer(8), "title": .string("New")])
            }, fetchMutationSnapshot: { id in
                #expect(id == "tip")
                return .object(["session_id": .string("tip"), "exists": .bool(true), "runtime_revision": .integer(7), "runtime_generation": .integer(2)])
            })
        #expect(methods == ["session.resume", "session.mutate"])
        #expect(store.cursors["tip"] == nil)
        #expect(store.cursors["owner"]?.revision == 91)
        #expect(store.cursors["owner"]?.generation == 8)
        try await store.mutate("tip", operation: "model", payload: ["model": .string("model")], requiresGeneration: true,
            rpc: { method, params in
                #expect(method == "session.mutate")
                #expect(params["session_id"] == .string("owner"))
                #expect(params["expected_revision"] == .integer(91))
                #expect(params["expected_generation"] == .integer(8))
                return .object(["session_id": .string("owner"), "revision": .integer(92), "execution_generation": .integer(9)])
            })
        #expect(store.cursors["owner"]?.revision == 92)
        #expect(store.cursors["owner"]?.generation == 9)
    }

    @Test @MainActor func staleReceiptCannotRemoveOtherProfileSubmissionOrSendResume() async throws {
        let store = HermesStore()
        store.credentials = GatewayCredentials(endpoint: "https://example.test", token: "dummy")
        store.profileID = "profile-a"
        store.accountID = "account-a"
        let pending = PendingSubmission(id: "pending-a", endpoint: "https://example.test", profileID: "profile-a", sessionID: "session-a",
            text: "Message", attachments: [], createdAt: .now, admissionID: "admission-a", accountID: "account-a")
        store.submissions = [pending]
        var methods: [String] = []
        do {
            try await store.resume("session-a", rpc: { method, _ in
                methods.append(method)
                switchToOtherProfile(store)
                // Even if the other profile now owns an identically named pending item,
                // an old terminal receipt cannot remove it or overwrite B's errors.
                store.submissions = [pending]
                return .object(["status": .string("terminal")])
            })
            Issue.record("The old profile resume must cancel")
        } catch is CancellationError { }
        #expect(methods == ["prompt.receipt"])
        #expect(store.submissions == [pending])
        #expect(store.selectedThreadID == nil)
        #expect(store.isLoadingMessages)
        #expect(store.lastError == "Profile B error")
    }

    @Test @MainActor func staleReplayCannotRequestReplacementSnapshotOrClearNewLoadingState() async throws {
        let store = HermesStore()
        store.cursors["session-a"] = SessionCursor()
        var methods: [String] = []
        do {
            try await store.resume("session-a", rpc: { method, _ in
                methods.append(method)
                if method == "session.resume" { return snapshot("session-a") }
                switchToOtherProfile(store)
                return .object(["snapshot_required": .bool(true)])
            })
            Issue.record("The stale replay must cancel")
        } catch is CancellationError { }
        #expect(methods == ["session.resume", "session.events.since"])
        #expect(store.selectedThreadID == nil)
        #expect(store.cursors.isEmpty)
        #expect(store.isLoadingMessages)
        #expect(store.lastError == "Profile B error")
    }

    @Test @MainActor func staleDetachCreateAndMetadataSnapshotNeverStartFollowupOnNewProfile() async throws {
        let store = HermesStore()
        store.selectedThreadID = "previous"
        var cursor = SessionCursor()
        cursor.subscriptionID = "subscription"
        store.cursors["previous"] = cursor
        var methods: [String] = []
        await store.openThread("next", rpc: { method, _ in
            methods.append(method)
            switchToOtherProfile(store)
            throw GatewayError.timeout
        })
        #expect(methods == ["session.detach"])
        #expect(store.lastError == "Profile B error")
        #expect(store.isLoadingMessages)

        store.isLoadingMessages = false
        store.runtime = .object(["session_create": .object(["sources": .array([.string("gui")])])])
        methods = []
        await store.createThread(rpc: { method, _ in
            methods.append(method)
            switchToOtherProfile(store)
            return snapshot("old-profile-created")
        })
        #expect(methods == ["session.create"])
        #expect(store.selectedThreadID == nil)
        #expect(store.isLoadingMessages)
        #expect(store.lastError == "Profile B error")

        store.cursors = [:]
        methods = []
        do {
            try await store.mutate("tip", operation: "rename", payload: ["title": .string("New")], requiresGeneration: false,
                rpc: { method, _ in methods.append(method); return snapshot("owner") },
                fetchMutationSnapshot: { _ in
                    switchToOtherProfile(store)
                    return .object(["session_id": .string("tip"), "exists": .bool(true), "runtime_revision": .integer(7), "runtime_generation": .integer(2)])
                })
            Issue.record("The stale metadata snapshot must cancel")
        } catch is CancellationError { }
        #expect(methods == ["session.resume"])
        #expect(store.cursors.isEmpty)
        #expect(store.lastError == "Profile B error")
    }

    @Test @MainActor func staleMutationReplyCannotRefreshOrUpdateOtherProfileCursorsAndErrors() async throws {
        let store = HermesStore()
        store.cursors["old"] = SessionCursor()
        var methods: [String] = []
        await store.renameThread("old", title: "New", rpc: { method, _ in
            methods.append(method)
            switchToOtherProfile(store)
            var current = SessionCursor()
            current.revision = 100
            store.cursors["old"] = current
            throw GatewayError.timeout
        })
        #expect(methods == ["session.mutate"])
        #expect(store.cursors["old"]?.revision == 100)
        #expect(store.lastError == "Profile B error")
        #expect(store.isLoadingMessages)
    }

    @Test @MainActor func staleInitialResumeAndArchiveSuccessCannotInstallOrRemoveNewProfileState() async throws {
        let store = HermesStore()
        do {
            try await store.resume("session-a", rpc: { _, _ in
                switchToOtherProfile(store)
                return snapshot("session-a")
            })
            Issue.record("The stale snapshot must cancel")
        } catch is CancellationError { }
        #expect(store.selectedThreadID == nil)
        #expect(store.cursors.isEmpty)
        #expect(store.isLoadingMessages)

        store.cursors["shared-id"] = SessionCursor()
        await store.archiveThread("shared-id", rpc: { _, _ in
            switchToOtherProfile(store)
            let kept = HistoryThreadRow(thread: HermesThread(id: "shared-id", title: "Profile B conversation"))
            store.threadHistory.rows = [kept]
            store.threads = [kept.thread]
            return .object(["session_id": .string("shared-id"), "revision": .integer(1), "archived": .bool(true)])
        })
        #expect(store.threads.first?.title == "Profile B conversation")
        #expect(store.threadHistory.rows.count == 1)
        #expect(store.lastError == "Profile B error")
        #expect(store.isLoadingMessages)
    }

    @Test @MainActor func resetLineageUsesOneConversationWhileIndependentBranchesRemainSeparate() async throws {
        let old = row("old-reset", extra: ["source": .string("local"), "chat_id": .string("owner")])
        let head = row("current-reset", extra: ["source": .string("local"), "chat_id": .string("owner"),
            "_lineage_ids": .array([.string("owner"), .string("old-reset"), .string("current-reset")])])
        let live = row("owner", title: "Current logical conversation", extra: ["session_id": .string("owner"), "running": .bool(true)])
        let branch = row("branch", extra: ["source": .string("local"), "chat_id": .string("branch")])
        let rows = try [HistoryThreadRow(old, canonical: false), HistoryThreadRow(head, canonical: false),
            HistoryThreadRow(branch, canonical: false), HistoryThreadRow(live, canonical: true)]
        let merged = HermesStore.mergeHistoryRows(rows)
        #expect(Set(merged.map { $0.thread.id }) == ["owner", "branch"])
        #expect(merged.first { $0.thread.id == "owner" }?.aliases.isSuperset(of: ["owner", "old-reset", "current-reset"]) == true)
    }

}
