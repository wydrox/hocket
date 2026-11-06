import Foundation

typealias StoredTranscriptFetch = @MainActor (String, String, Int) async throws -> StoredTranscriptPage

extension HermesStore {
    func resetStoredTranscript() {
        storedTranscript = nil
        isReadOnlyConversation = false
        hasOlderMessages = false
        isLoadingOlderMessages = false
        olderMessagesError = nil
    }

    /// A REST-listed physical row can be readable while native legacy adoption is refused.
    /// This never upgrades a refusal into a canonical/writable session.
    func storedTranscriptSource(for id: String, refusal: any Error) -> StoredTranscriptState? {
        guard let error = refusal as? GatewayRPCError, error.code == 4001,
              error.data?["reason"].string == "not_found" else { return nil }
        let profile = selectedProfileName ?? profiles.first(where: { $0.path == profileID })?.name
        guard let profile, !profile.isEmpty else { return nil }
        let physicalID: String?
        if threadHistory.scope == currentHistoryScope,
           let listed = threadHistory.rows.first(where: { $0.aliases.contains(id) }) {
            physicalID = listed.thread.id
        } else if let previous = storedTranscript, previous.selectionID == id,
                  previous.scope == currentHistoryScope, previous.profile == profile {
            physicalID = previous.physicalID
        } else { physicalID = nil }
        guard let physicalID else { return nil }
        return StoredTranscriptState(selectionID: id, physicalID: physicalID, profile: profile,
            scope: currentHistoryScope, nextOffset: 0)
    }

    func fetchStoredPage(physicalID: String, profile: String, offset: Int, fetch: StoredTranscriptFetch?) async throws -> StoredTranscriptPage {
        let page: StoredTranscriptPage
        if let fetch { page = try await fetch(physicalID, profile, offset) }
        else {
            guard let credentials else { throw GatewayError.disconnected }
            page = try await StoredTranscriptClient().load(credentials: credentials,
                sessionID: physicalID, profile: profile, offset: offset)
        }
        let (nextOffset, overflow) = offset.addingReportingOverflow(page.rawCount)
        guard !overflow, page.profile == profile, page.nextOffset == nextOffset else {
            throw GatewayError.invalidResponse("Hermes returned a different conversation page. Reload it in its original profile.")
        }
        return page
    }

    func installStoredTranscript(_ page: StoredTranscriptPage, source: StoredTranscriptState) {
        activateDraft(sessionID: source.selectionID)
        selectedThreadID = source.selectionID
        selectedThreadTitle = threads.first(where: { $0.id == source.selectionID })?.title ?? "Saved conversation"
        isReadOnlyConversation = true
        isStreaming = false
        messages = page.messages
        cursors.removeValue(forKey: source.selectionID)
        pendingInteraction = nil
        interactions.removeAll { $0.sessionID == source.selectionID }
        selectedModel = ""
        selectedEffort = ""
        selectedServiceTier = "normal"
        var installed = source
        installed.nextOffset = page.nextOffset
        storedTranscript = installed
        hasOlderMessages = page.hasOlder
        olderMessagesError = nil
        isLoadingOlderMessages = false
    }

    func loadOlderMessages(fetch: StoredTranscriptFetch? = nil) async {
        guard isReadOnlyConversation, hasOlderMessages, !isLoadingMessages, !isLoadingOlderMessages,
              let source = storedTranscript, source.scope == currentHistoryScope,
              source.selectionID == selectedThreadID else { return }
        let connection = connectionAttempt, navigation = navigationAttempt
        isLoadingOlderMessages = true
        olderMessagesError = nil
        defer {
            if connectionAttempt == connection, navigationAttempt == navigation {
                isLoadingOlderMessages = false
            }
        }
        do {
            let page = try await fetchStoredPage(physicalID: source.physicalID, profile: source.profile,
                offset: source.nextOffset, fetch: fetch)
            try checkConnectionAttempt(connection)
            guard navigationAttempt == navigation, source.scope == currentHistoryScope,
                  storedTranscript == source, isReadOnlyConversation else { return }
            var ids = Set(messages.map(\.id))
            let earlier = page.messages.filter { ids.insert($0.id).inserted }
            messages = earlier + messages
            storedTranscript?.nextOffset = page.nextOffset
            hasOlderMessages = page.hasOlder
        } catch {
            guard connectionAttempt == connection, navigationAttempt == navigation else { return }
            if !(error is CancellationError) { olderMessagesError = error.localizedDescription }
        }
    }

    func requireWritableConversation() throws {
        guard !isReadOnlyConversation else {
            throw GatewayError.invalidResponse("This saved conversation is read-only through this connection. Start a new conversation to send a message.")
        }
    }
}
