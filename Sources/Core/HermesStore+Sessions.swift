import Foundation

typealias SessionRPC = @MainActor (String, [String: JSONValue]) async throws -> JSONValue
typealias SessionMutationSnapshotFetch = @MainActor (String) async throws -> JSONValue

extension HermesStore {
    func refreshThreads(query: String? = nil) async {
        do { try await loadThreads(query: query ?? threadSearchQuery) } catch { /* The current request owns its error. */ }
    }

    var currentHistoryScope: ThreadHistoryScope {
        ThreadHistoryScope(endpoint: credentials?.endpoint, account: accountID, profile: profileID, profileName: credentials?.profileName)
    }

    func resetThreadHistory() {
        listRequestID = UUID()
        threadHistory = ThreadHistoryState()
        isLoadingThreads = false
        isLoadingOlderThreads = false
        hasOlderThreads = false
        threadHistoryError = nil
    }

    func setThreadSearchQuery(_ query: String) {
        threadSearchQuery = query
        rebuildThreadList()
    }

    func loadThreads(query: String) async throws {
        guard let saved = credentials else { throw GatewayError.disconnected }
        try await loadThreads(query: query, fetchSessions: { scope in
            try await self.transport.call("session.list", params: ["scope": .string(scope), "limit": .integer(200), "include_hidden": .bool(false)])
        }, fetchHistory: { offset in
            try await ThreadHistoryClient().load(credentials: saved, offset: offset)
        })
    }

    func loadThreads(query: String, fetchSessions: (String) async throws -> JSONValue,
                     fetchHistory: (Int) async throws -> JSONValue) async throws {
        let scope = currentHistoryScope
        if threadHistory.scope != nil && threadHistory.scope != scope { resetThreadHistory() }
        isLoadingThreads = true
        isLoadingOlderThreads = false
        hasLoadedThreads = false
        threadSearchQuery = query
        threadListError = nil
        threadHistoryError = nil
        let requestID = UUID()
        listRequestID = requestID
        defer { if listRequestID == requestID { isLoadingThreads = false } }
        var loadingHistory = false
        do {
            let stored = try Self.canonicalThreadRows(try await fetchSessions("stored"), scope: "stored")
            guard listRequestID == requestID, currentHistoryScope == scope else { return }
            let live = try Self.canonicalThreadRows(try await fetchSessions("live"), scope: "live")
            guard listRequestID == requestID, currentHistoryScope == scope else { return }
            loadingHistory = true
            let page = try ThreadHistoryPage(try await fetchHistory(0), expectedOffset: 0)
            guard listRequestID == requestID, currentHistoryScope == scope else { return }
            // Keep already discovered older pages while refreshing recency. Pagination restarts at
            // the first page; overlap is expected for pins and conversations with fresh activity.
            let previous = threadHistory.scope == scope && page.total > 0
                ? threadHistory.rows.filter { $0.aliases.isDisjoint(with: threadHistory.firstPageAliases) } : []
            threadHistory.rows = Self.mergeHistoryRows(previous + page.rows)
            threadHistory.firstPageAliases = page.rows.reduce(into: Set<String>()) { $0.formUnion($1.aliases) }
            threadHistory.canonical = Self.mergeHistoryRows(stored + live)
            threadHistory.scope = scope
            threadHistory.nextOffset = page.nextOffset
            threadHistory.total = page.total
            hasOlderThreads = page.hasMore
            rebuildThreadList()
            hasLoadedThreads = true
            lastThreadsUpdatedAt = Date()
        } catch {
            guard listRequestID == requestID, currentHistoryScope == scope else { return }
            if !(error is CancellationError) {
                if loadingHistory { threadHistoryError = error.localizedDescription }
                threadListError = error.localizedDescription
            }
            throw error
        }
    }

    func loadOlderThreads() async {
        guard let saved = credentials else { return }
        do {
            try await loadOlderThreads(fetchHistory: { offset in
                try await ThreadHistoryClient().load(credentials: saved, offset: offset)
            })
        } catch { /* Pagination owns threadHistoryError; already loaded rows stay visible. */ }
    }

    func loadOlderThreads(fetchHistory: (Int) async throws -> JSONValue) async throws {
        guard hasOlderThreads, !isLoadingThreads, !isLoadingOlderThreads,
              threadHistory.scope == currentHistoryScope else { return }
        let generation = listRequestID, scope = currentHistoryScope, offset = threadHistory.nextOffset
        isLoadingOlderThreads = true
        threadHistoryError = nil
        defer { if listRequestID == generation, currentHistoryScope == scope { isLoadingOlderThreads = false } }
        do {
            let page = try ThreadHistoryPage(try await fetchHistory(offset), expectedOffset: offset)
            guard listRequestID == generation, currentHistoryScope == scope else { return }
            threadHistory.rows = Self.mergeHistoryRows(threadHistory.rows + page.rows)
            threadHistory.nextOffset = page.nextOffset
            threadHistory.total = page.total
            // A duplicate-only pinned page can precede unseen rows. The server's total bounds
            // those pages; an empty raw page handles totals inflated by hidden sessions.
            hasOlderThreads = page.hasMore
            rebuildThreadList()
            lastThreadsUpdatedAt = Date()
        } catch {
            guard listRequestID == generation, currentHistoryScope == scope else { return }
            if !(error is CancellationError) { threadHistoryError = error.localizedDescription }
            throw error
        }
    }

    private func rebuildThreadList() {
        var history = threadHistory.rows
        for index in history.indices {
            let aliases = history[index].aliases
            for alias in aliases {
                if let owner = threadHistory.resumedAliases[alias] { history[index].aliases.insert(owner) }
            }
        }
        let all = Self.mergeHistoryRows(history + threadHistory.canonical).map(\.thread)
        loadedConversationCount = all.count
        if let selected = all.first(where: { $0.id == selectedThreadID }) { selectedThreadTitle = selected.title }
        threads = Self.mergeThreads(stored: all, live: [], query: threadSearchQuery)
    }

    nonisolated static func canonicalThreadRows(_ result: JSONValue, scope: String) throws -> [HistoryThreadRow] {
        guard result["scope"].string == scope, let rows = result["sessions"].array else {
            throw GatewayError.invalidResponse("Hermes returned an invalid \(scope) conversation list. Try loading threads again.")
        }
        return try rows.map { try HistoryThreadRow($0, canonical: true) }
    }

    nonisolated static func threadRows(_ result: JSONValue, scope: String) throws -> [HermesThread] {
        try canonicalThreadRows(result, scope: scope).map(\.thread)
    }

    nonisolated static func mergeHistoryRows(_ rows: [HistoryThreadRow]) -> [HistoryThreadRow] {
        var merged: [HistoryThreadRow] = []
        for var row in rows {
            // Later canonical/live rows supply authoritative identity, title and running state.
            // Union all aliases so compressed physical IDs and their logical owner stay one row.
            let matches = merged.indices.filter { !merged[$0].aliases.isDisjoint(with: row.aliases) }
            for index in matches {
                let previous = merged[index]
                row.aliases.formUnion(previous.aliases)
                if let activity = previous.thread.updatedAt,
                   activity > (row.thread.updatedAt ?? .distantPast) { row.thread.updatedAt = activity }
                if row.thread.preview.isEmpty { row.thread.preview = previous.thread.preview }
            }
            for index in matches.reversed() { merged.remove(at: index) }
            merged.append(row)
        }
        return merged
    }

    nonisolated static func mergeThreads(stored: [HermesThread], live: [HermesThread], query: String) -> [HermesThread] {
        var byID: [String: HermesThread] = [:]
        for thread in stored + live { byID[thread.id] = thread }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return byID.values.filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || $0.preview.localizedStandardContains(query)
        }.sorted {
            let lhs = $0.updatedAt ?? .distantPast, rhs = $1.updatedAt ?? .distantPast
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
    }

    private func sessionCall(_ method: String, params: [String: JSONValue], attempt: UUID, rpc: SessionRPC?) async throws -> JSONValue {
        try checkConnectionAttempt(attempt)
        let result: JSONValue
        if let rpc { result = try await rpc(method, params) }
        else { result = try await transport.call(method, params: params) }
        try checkConnectionAttempt(attempt)
        return result
    }

    func openThread(_ id: String, rpc: SessionRPC? = nil, fetchStoredTranscript: StoredTranscriptFetch? = nil) async {
        guard !isLoadingMessages else { return }
        let connection = connectionAttempt
        let navigation = UUID()
        navigationAttempt = navigation
        openingThreadID = id
        threadOpenErrorID = nil
        threadOpenError = nil
        isLoadingMessages = true
        isLoadingOlderMessages = false
        defer {
            if connectionAttempt == connection, navigationAttempt == navigation {
                openingThreadID = nil
                isLoadingMessages = false
            }
        }
        lastError = nil
        saveDraft()
        let oldID = selectedThreadID
        do {
            if let oldID, oldID != id, let subscription = cursors[oldID]?.subscriptionID {
                _ = try await sessionCall("session.detach", params: ["session_id": .string(oldID), "subscription_id": .string(subscription)], attempt: connection, rpc: rpc)
            }
            try checkConnectionAttempt(connection)
            try await resume(id, rpc: rpc, fetchStoredTranscript: fetchStoredTranscript, navigation: navigation)
            try checkConnectionAttempt(connection)
            guard navigationAttempt == navigation else { throw CancellationError() }
            openingThreadID = nil
            isLoadingMessages = false
            if !isReadOnlyConversation { await loadCatalogs() }
            try checkConnectionAttempt(connection)
        } catch {
            guard connectionAttempt == connection, navigationAttempt == navigation else { return }
            if error is CancellationError { return }
            threadOpenErrorID = id
            threadOpenError = error.localizedDescription
            report(error)
        }
    }

    func resume(_ id: String, rpc: SessionRPC? = nil, fetchStoredTranscript: StoredTranscriptFetch? = nil,
                navigation: UUID? = nil) async throws {
        let connection = connectionAttempt
        isLoadingMessages = true
        let attempt = navigation ?? UUID()
        navigationAttempt = attempt
        defer { if navigation == nil, connectionAttempt == connection, navigationAttempt == attempt { isLoadingMessages = false } }
        let oldCursor = cursors[id]
        if !(isReadOnlyConversation && storedTranscript?.selectionID == id) {
            try await reconcileReceipts(sessionID: id, rpc: rpc)
        }
        try checkConnectionAttempt(connection)
        guard navigationAttempt == attempt else { throw CancellationError() }
        let snapshot: JSONValue
        do {
            snapshot = try await sessionCall("session.resume", params: ["session_id": .string(id)], attempt: connection, rpc: rpc)
        } catch {
            try checkConnectionAttempt(connection)
            guard navigationAttempt == attempt else { throw CancellationError() }
            guard let source = storedTranscriptSource(for: id, refusal: error) else { throw error }
            let page = try await fetchStoredPage(physicalID: source.physicalID, profile: source.profile,
                offset: 0, fetch: fetchStoredTranscript)
            try checkConnectionAttempt(connection)
            guard navigationAttempt == attempt, source.scope == currentHistoryScope else { throw CancellationError() }
            installStoredTranscript(page, source: source)
            let buffered = bufferedEvents
            bufferedEvents = []
            for event in buffered { applyEvent(event) }
            return
        }
        guard navigationAttempt == attempt else { throw CancellationError() }
        try installSnapshot(snapshot, requestedID: id)
        let owner = selectedThreadID ?? id
        // Replay uses the same canonical identity and fences that the snapshot installed.
        if oldCursor != nil, let cursor = cursors[owner], let epoch = cursor.replayEpoch {
            let replay = try await sessionCall("session.events.since", params: ["session_id": .string(owner), "last_sequence": .integer(cursor.sequence), "replay_epoch": .string(epoch)], attempt: connection, rpc: rpc)
            guard navigationAttempt == attempt else { throw CancellationError() }
            if replay["snapshot_required"].bool == true || replay["truncated"].bool == true {
                let replacement = try await sessionCall("session.resume", params: ["session_id": .string(owner)], attempt: connection, rpc: rpc)
                guard navigationAttempt == attempt else { throw CancellationError() }
                try installSnapshot(replacement, requestedID: id)
            } else {
                for event in replay["events"].array ?? [] { applyEvent(event) }
            }
        }
        try checkConnectionAttempt(connection)
        guard navigationAttempt == attempt else { throw CancellationError() }
        let buffered = bufferedEvents
        bufferedEvents = []
        for event in buffered { applyEvent(event) }
    }

    func installSnapshot(_ snapshot: JSONValue, requestedID: String? = nil) throws {
        guard let id = snapshot["session_id"].string, snapshot["info"]["desktop_protocol"].string == "hermes-gateway-v1" else {
            throw GatewayError.unsupportedAuthority
        }
        resetStoredTranscript()
        if let requestedID, requestedID != id { threadHistory.resumedAliases[requestedID] = id }
        activateDraft(sessionID: id)
        selectedThreadID = id
        var cursor = cursors[id] ?? SessionCursor()
        cursor.installSnapshot(snapshot)
        cursors[id] = cursor
        isStreaming = snapshot["running"].bool ?? false
        messages = (snapshot["messages"].array ?? []).enumerated().compactMap { offset, row in
            Self.message(row, fallbackID: "\(id):history:\(offset)")
        }
        let persistedSubmissionIDs = Set((snapshot["messages"].array ?? []).compactMap { $0["submission_id"].string })
        for submission in submissions where submission.sessionID == id && submission.profileID == profileID && submission.endpoint == credentials?.endpoint && submission.accountID == accountID {
            // Accepted admissions are represented by the server snapshot. Only unacknowledged
            // local inputs need a retry bubble; never duplicate an accepted user row by text.
            if submission.admissionID == nil, !persistedSubmissionIDs.contains(submission.id) {
                messages.append(ChatMessage(id: submission.id, role: .user, text: AttachmentProjection.extract(submission.text).text,
                    status: .failed, createdAt: submission.createdAt, attachments: submission.attachments.map(MessageAttachment.staged)))
            }
        }
        interactions.removeAll { $0.sessionID == id }
        for prompt in snapshot["prompts"].array ?? [] { enqueuePrompt(prompt, sessionID: id) }
        for request in snapshot["open_requests"].array ?? [] { restoreServerRequest(request, sessionID: id) }
        refreshPendingInteraction()
        applyInfo(snapshot["info"])
        let existing = threads.first { $0.id == id || threadHistory.resumedAliases[$0.id] == id }
        let info = snapshot["info"]
        let title = info["title"].string.flatMap { $0.isEmpty ? nil : $0 } ?? existing?.title ?? "Untitled conversation"
        selectedThreadTitle = title
        let thread = HermesThread(id: id, title: title, preview: existing?.preview ?? "",
            updatedAt: Self.date(info.object?["last_active_at"] ?? info["started_at"]) ?? existing?.updatedAt,
            messageCount: Int(snapshot["message_count"].int ?? Int64(messages.count)), isRunning: isStreaming,
            isArchived: existing?.isArchived ?? false)
        let aliases = Set(threadHistory.resumedAliases.filter { $0.value == id }.map(\.key)).union([id])
        threadHistory.canonical = Self.mergeHistoryRows(threadHistory.canonical + [HistoryThreadRow(thread: thread, aliases: aliases)])
        // Snapshots can arrive before the first list refresh, so retain any visible local row.
        if threadHistory.rows.isEmpty && threadHistory.canonical.count == 1 {
            threadHistory.canonical = Self.mergeHistoryRows(threads.map { HistoryThreadRow(thread: $0) } + threadHistory.canonical)
        }
        rebuildThreadList()
    }

    func createThread(rpc: SessionRPC? = nil) async {
        guard !isLoadingMessages else { return }
        let connection = connectionAttempt, navigation = UUID()
        navigationAttempt = navigation
        openingThreadID = nil
        threadOpenErrorID = nil
        threadOpenError = nil
        lastError = nil
        saveDraft()
        isLoadingMessages = true
        defer { if connectionAttempt == connection, navigationAttempt == navigation { isLoadingMessages = false } }
        do {
            let sources = runtime["session_create"]["sources"].array?.compactMap(\.string) ?? []
            guard sources.contains("gui") else { throw GatewayError.invalidResponse("This Hermes server does not accept native GUI conversations.") }
            let requestID = createRequestID ?? UUID().uuidString
            createRequestID = requestID
            let snapshot = try await sessionCall("session.create", params: ["request_id": .string(requestID), "source": .string("gui")], attempt: connection, rpc: rpc)
            guard navigationAttempt == navigation else { throw CancellationError() }
            try installSnapshot(snapshot)
            createRequestID = nil
            let buffered = bufferedEvents
            bufferedEvents = []
            for event in buffered { applyEvent(event) }
            await refreshThreads(query: threadSearchQuery)
            try checkConnectionAttempt(connection)
            guard navigationAttempt == navigation else { throw CancellationError() }
            await loadCatalogs()
            try checkConnectionAttempt(connection)
        } catch {
            guard connectionAttempt == connection, navigationAttempt == navigation else { return }
            report(error)
        }
    }

    func renameThread(_ id: String, title: String, rpc: SessionRPC? = nil,
                      fetchMutationSnapshot: SessionMutationSnapshotFetch? = nil) async {
        let connection = connectionAttempt
        lastError = nil
        do {
            try await mutate(id, operation: "rename", payload: ["title": .string(title)], requiresGeneration: false,
                rpc: rpc, fetchMutationSnapshot: fetchMutationSnapshot)
            try checkConnectionAttempt(connection)
            await refreshThreads(query: threadSearchQuery)
            try checkConnectionAttempt(connection)
        } catch {
            guard connectionAttempt == connection else { return }
            report(error)
        }
    }

    func archiveThread(_ id: String, rpc: SessionRPC? = nil,
                       fetchMutationSnapshot: SessionMutationSnapshotFetch? = nil) async {
        let connection = connectionAttempt
        lastError = nil
        do {
            try await mutate(id, operation: "archive", payload: ["archived": .bool(true)], requiresGeneration: false,
                rpc: rpc, fetchMutationSnapshot: fetchMutationSnapshot)
            try checkConnectionAttempt(connection)
            let aliases = mutationAliases(for: id)
            threadHistory.rows.removeAll { !$0.aliases.isDisjoint(with: aliases) }
            threadHistory.canonical.removeAll { !$0.aliases.isDisjoint(with: aliases) }
            rebuildThreadList()
            await refreshThreads(query: threadSearchQuery)
            try checkConnectionAttempt(connection)
        } catch {
            guard connectionAttempt == connection else { return }
            report(error)
        }
    }

    private func mutationAliases(for id: String) -> Set<String> {
        var aliases: Set<String> = [id]
        if let owner = threadHistory.resumedAliases[id] { aliases.insert(owner) }
        for row in threadHistory.rows + threadHistory.canonical where !row.aliases.isDisjoint(with: aliases) {
            aliases.formUnion(row.aliases)
        }
        return aliases
    }

    private func installMutationTitle(_ title: String, id: String) {
        let aliases = mutationAliases(for: id)
        for index in threadHistory.rows.indices where !threadHistory.rows[index].aliases.isDisjoint(with: aliases) {
            threadHistory.rows[index].thread.title = title.isEmpty ? "Untitled conversation" : title
        }
        for index in threadHistory.canonical.indices where !threadHistory.canonical[index].aliases.isDisjoint(with: aliases) {
            threadHistory.canonical[index].thread.title = title.isEmpty ? "Untitled conversation" : title
        }
        rebuildThreadList()
    }

    @discardableResult
    func mutate(_ id: String, operation: String, payload: [String: JSONValue], requiresGeneration: Bool,
                rpc: SessionRPC? = nil, fetchMutationSnapshot: SessionMutationSnapshotFetch? = nil) async throws -> JSONValue {
        try requireWritableConversation()
        let connection = connectionAttempt
        var owner = threadHistory.resumedAliases[id] ?? id
        if cursors[owner] == nil {
            let snapshot = try await sessionCall("session.resume", params: ["session_id": .string(id)], attempt: connection, rpc: rpc)
            guard let canonicalID = snapshot["session_id"].string, !canonicalID.isEmpty,
                  snapshot["info"]["desktop_protocol"].string == "hermes-gateway-v1" else { throw GatewayError.unsupportedAuthority }
            owner = canonicalID
            if owner != id { threadHistory.resumedAliases[id] = owner }
            var cursor = SessionCursor()
            cursor.installSnapshot(snapshot)
            cursors[owner] = cursor
        }
        try checkConnectionAttempt(connection)
        guard var cursor = cursors[owner] else { throw GatewayError.missingSession }
        // Metadata belongs to the listed segment, whereas live policy/transcript controls use
        // the resumed owner. A segment's revision is never the owner's snapshot revision.
        let metadata = ["rename", "archive", "sidebar"].contains(operation)
        let target = metadata ? id : owner
        if target != owner {
            let snapshot: JSONValue
            if let fetchMutationSnapshot { snapshot = try await fetchMutationSnapshot(target) }
            else { snapshot = try await physicalMutationSnapshot(target) }
            try checkConnectionAttempt(connection)
            guard snapshot["session_id"].string == target, snapshot["exists"].bool == true,
                  let revision = snapshot["runtime_revision"].int, revision >= 0,
                  let generation = snapshot["runtime_generation"].int, generation >= 0 else {
                throw GatewayError.invalidResponse("Hermes did not return the selected conversation's mutation fences.")
            }
            cursor.revision = revision
            cursor.generation = generation
        }
        try checkConnectionAttempt(connection)
        var params: [String: JSONValue] = ["session_id": .string(target), "request_id": .string(UUID().uuidString),
            "expected_revision": .integer(cursor.revision), "operation": .string(operation), "payload": .object(payload)]
        if requiresGeneration { params["expected_generation"] = .integer(cursor.generation) }
        do {
            let result = try await sessionCall("session.mutate", params: params, attempt: connection, rpc: rpc)
            if let confirmation = ModelSelectionConfirmation(result) { throw confirmation }
            if target == owner {
                cursors[owner]?.revision = result["revision"].int ?? cursor.revision
                cursors[owner]?.generation = result["execution_generation"].int ?? cursor.generation
            }
            if operation == "rename", let title = result["title"].string { installMutationTitle(title, id: id) }
            if selectedThreadID == owner {
                try await resume(owner, rpc: rpc)
                try checkConnectionAttempt(connection)
            }
            return result
        } catch {
            try checkConnectionAttempt(connection)
            // Refresh the owner's fences, but never repeat the user's mutation automatically.
            if let refusal = error as? GatewayRPCError, refusal.code == 4001, selectedThreadID == owner {
                do {
                    try await resume(owner, rpc: rpc)
                    try checkConnectionAttempt(connection)
                } catch {
                    try checkConnectionAttempt(connection)
                    report(error)
                }
            }
            throw error
        }
    }

    private func physicalMutationSnapshot(_ id: String) async throws -> JSONValue {
        guard let saved = credentials,
              let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))),
              var parts = URLComponents(url: try GatewayEndpoint(saved.endpoint).httpURL(path: "api/sessions"), resolvingAgainstBaseURL: false) else {
            throw GatewayError.missingSession
        }
        parts.percentEncodedPath += "/\(encodedID)/mutation-snapshot"
        if let profile = saved.profileName, !profile.isEmpty { parts.queryItems = [URLQueryItem(name: "profile", value: profile)] }
        guard let url = parts.url else { throw GatewayError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidFrame }
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 { throw GatewayError.authentication(response.statusCode) }
            throw GatewayError.invalidResponse("Hermes could not load conversation mutation fences (HTTP \(response.statusCode)). Try again.")
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    nonisolated static func date(_ value: JSONValue) -> Date? {
        if let string = value.string { return try? Date(string, strategy: .iso8601) }
        if let seconds = value.int { return Date(timeIntervalSince1970: Double(seconds)) }
        if case .number(let seconds) = value { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    nonisolated static func message(_ row: JSONValue, fallbackID: String) -> ChatMessage? {
        guard let roleString = row["role"].string, let role = MessageRole(rawValue: roleString) else { return nil }
        let projection = AttachmentProjection.message(row)
        return ChatMessage(id: row["row_id"].identifier.map { "row:\($0)" } ?? row["id"].identifier ?? fallbackID,
            role: role, text: projection.text, reasoning: row["reasoning"].string ?? "", createdAt: date(row["timestamp"]), toolName: row["name"].string,
            attachments: projection.attachments)
    }

    func reconcileReceipts(sessionID: String, rpc: SessionRPC? = nil) async throws {
        let connection = connectionAttempt
        let outstanding = submissions.filter { $0.sessionID == sessionID && $0.profileID == profileID && $0.endpoint == credentials?.endpoint && $0.accountID == accountID && $0.admissionID != nil }
        for submission in outstanding {
            try checkConnectionAttempt(connection)
            guard let admission = submission.admissionID else { continue }
            let receipt = try await sessionCall("prompt.receipt", params: ["session_id": .string(sessionID), "admission_id": .string(admission), "include_result": .bool(true)], attempt: connection, rpc: rpc)
            if receipt["status"].string == "terminal" { submissions.removeAll { $0.id == submission.id } }
            else if receipt["status"].string == "unknown" { lastError = "An accepted message has unknown execution state after a Hermes restart. Resolve it on the server before sending it again." }
        }
        try checkConnectionAttempt(connection)
        if !outstanding.isEmpty { try journal.save(submissions) }
    }
}
