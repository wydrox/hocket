import Foundation

extension HermesStore {
    func refreshThreads(query: String = "") async {
        lastError = nil
        do { try await loadThreads(query: query) } catch { report(error) }
    }

    func loadThreads(query: String) async throws {
        isLoadingThreads = true
        let requestID = UUID()
        listRequestID = requestID
        defer { if listRequestID == requestID { isLoadingThreads = false } }
        var params: [String: JSONValue] = ["scope": .string("stored"), "limit": .integer(200), "include_hidden": .bool(false)]
        if !query.isEmpty { params["title"] = .string(query) }
        let result = try await transport.call("session.list", params: params)
        guard listRequestID == requestID else { return }
        threads = (result["sessions"].array ?? []).compactMap { row in
            guard let id = row["session_id"].string ?? row["id"].string else { return nil }
            return HermesThread(id: id, title: row["title"].string ?? "Untitled conversation",
                preview: row["preview"].string ?? "", updatedAt: Self.date(row.object?["updated_at"] ?? row["started_at"]),
                messageCount: Int(row["message_count"].int ?? 0), isRunning: row["running"].bool ?? false,
                isArchived: row["archived"].bool ?? false)
        }
    }

    func openThread(_ id: String) async {
        guard !isLoadingMessages else { return }
        lastError = nil
        saveDraft()
        let oldID = selectedThreadID
        do {
            if let oldID, oldID != id, let subscription = cursors[oldID]?.subscriptionID {
                _ = try await transport.call("session.detach", params: ["session_id": .string(oldID), "subscription_id": .string(subscription)])
            }
            try await resume(id)
            await loadCatalogs()
        } catch { report(error) }
    }

    func resume(_ id: String) async throws {
        isLoadingMessages = true
        let attempt = UUID()
        navigationAttempt = attempt
        defer { isLoadingMessages = false }
        let oldCursor = cursors[id]
        try await reconcileReceipts(sessionID: id)
        let snapshot = try await transport.call("session.resume", params: ["session_id": .string(id)])
        guard navigationAttempt == attempt else { return }
        try installSnapshot(snapshot)
        // A fresh snapshot is authoritative. Replay after its cursor fills only events since it.
        if oldCursor != nil, let cursor = cursors[id], let epoch = cursor.replayEpoch {
            let replay = try await transport.call("session.events.since", params: ["session_id": .string(id), "last_sequence": .integer(cursor.sequence), "replay_epoch": .string(epoch)])
            if replay["snapshot_required"].bool == true || replay["truncated"].bool == true {
                let replacement = try await transport.call("session.resume", params: ["session_id": .string(id)])
                guard navigationAttempt == attempt else { return }
                try installSnapshot(replacement)
            } else {
                for event in replay["events"].array ?? [] { applyEvent(event) }
            }
        }
        let buffered = bufferedEvents
        bufferedEvents = []
        for event in buffered { applyEvent(event) }
    }

    func installSnapshot(_ snapshot: JSONValue) throws {
        guard let id = snapshot["session_id"].string, snapshot["info"]["desktop_protocol"].string == "hermes-gateway-v1" else {
            throw GatewayError.unsupportedAuthority
        }
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
                messages.append(ChatMessage(id: submission.id, role: .user, text: submission.text,
                    status: .failed, createdAt: submission.createdAt))
            }
        }
        interactions.removeAll { $0.sessionID == id }
        for prompt in snapshot["prompts"].array ?? [] { enqueuePrompt(prompt, sessionID: id) }
        for request in snapshot["open_requests"].array ?? [] { restoreServerRequest(request, sessionID: id) }
        refreshPendingInteraction()
        applyInfo(snapshot["info"])
    }

    func createThread() async {
        guard !isLoadingMessages else { return }
        lastError = nil
        saveDraft()
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        do {
            let sources = runtime["session_create"]["sources"].array?.compactMap(\.string) ?? []
            guard sources.contains("gui") else { throw GatewayError.invalidResponse("This Hermes server does not accept native GUI conversations.") }
            let requestID = createRequestID ?? UUID().uuidString
            createRequestID = requestID
            let snapshot = try await transport.call("session.create", params: ["request_id": .string(requestID), "source": .string("gui")])
            try installSnapshot(snapshot)
            createRequestID = nil
            let buffered = bufferedEvents
            bufferedEvents = []
            for event in buffered { applyEvent(event) }
            try await loadThreads(query: "")
            await loadCatalogs()
        } catch { report(error) }
    }

    func renameThread(_ id: String, title: String) async {
        lastError = nil
        do { try await mutate(id, operation: "rename", payload: ["title": .string(title)], requiresGeneration: false); try await loadThreads(query: "") }
        catch { report(error) }
    }

    func archiveThread(_ id: String) async {
        lastError = nil
        do { try await mutate(id, operation: "archive", payload: ["archived": .bool(true)], requiresGeneration: false); try await loadThreads(query: "") }
        catch { report(error) }
    }

    func mutate(_ id: String, operation: String, payload: [String: JSONValue], requiresGeneration: Bool) async throws {
        if cursors[id] == nil {
            let snapshot = try await transport.call("session.resume", params: ["session_id": .string(id)])
            var cursor = SessionCursor()
            cursor.installSnapshot(snapshot)
            cursors[id] = cursor
        }
        guard let cursor = cursors[id] else { throw GatewayError.missingSession }
        var params: [String: JSONValue] = ["session_id": .string(id), "request_id": .string(UUID().uuidString),
            "expected_revision": .integer(cursor.revision), "operation": .string(operation), "payload": .object(payload)]
        if requiresGeneration { params["expected_generation"] = .integer(cursor.generation) }
        do {
            let result = try await transport.call("session.mutate", params: params)
            cursors[id]?.revision = result["revision"].int ?? cursor.revision
            cursors[id]?.generation = result["execution_generation"].int ?? cursor.generation
            if selectedThreadID == id { try await resume(id) }
        } catch {
            // Refresh fences, but never repeat the user's mutation automatically.
            if let rpc = error as? GatewayRPCError, rpc.code == 4001, selectedThreadID == id {
                do { try await resume(id) } catch { report(error) }
            }
            throw error
        }
    }

    nonisolated static func date(_ value: JSONValue) -> Date? {
        if let string = value.string { return try? Date(string, strategy: .iso8601) }
        if let seconds = value.int { return Date(timeIntervalSince1970: Double(seconds)) }
        if case .number(let seconds) = value { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    nonisolated static func message(_ row: JSONValue, fallbackID: String) -> ChatMessage? {
        guard let roleString = row["role"].string, let role = MessageRole(rawValue: roleString) else { return nil }
        let content = row["content"]
        let text = content.string ?? content.array?.compactMap { $0["text"].string }.joined(separator: "\n") ?? row["text"].string ?? ""
        return ChatMessage(id: row["row_id"].identifier.map { "row:\($0)" } ?? row["id"].identifier ?? fallbackID,
            role: role, text: text, reasoning: row["reasoning"].string ?? "", createdAt: date(row["timestamp"]), toolName: row["name"].string)
    }

    func reconcileReceipts(sessionID: String) async throws {
        let outstanding = submissions.filter { $0.sessionID == sessionID && $0.profileID == profileID && $0.endpoint == credentials?.endpoint && $0.accountID == accountID && $0.admissionID != nil }
        for submission in outstanding {
            guard let admission = submission.admissionID else { continue }
            let receipt = try await transport.call("prompt.receipt", params: ["session_id": .string(sessionID), "admission_id": .string(admission), "include_result": .bool(true)])
            if receipt["status"].string == "terminal" { submissions.removeAll { $0.id == submission.id } }
            else if receipt["status"].string == "unknown" { lastError = "An accepted message has unknown execution state after a Hermes restart. Resolve it on the server before sending it again." }
        }
        if !outstanding.isEmpty { try journal.save(submissions) }
    }
}
