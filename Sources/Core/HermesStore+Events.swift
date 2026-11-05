import Foundation

extension HermesStore {
    func receiveEvent(_ event: JSONValue) {
        if isLoadingMessages { bufferedEvents.append(event); return }
        applyEvent(event)
    }

    func applyEvent(_ event: JSONValue) {
        let type = event["type"].string ?? ""
        if type == "sessions.changed" { scheduleRefresh(); return }
        if type == "skills.changed" { Task { [weak self] in await self?.loadCatalogs() }; return }
        guard let id = event["session_id"].string, id == selectedThreadID else { return }
        var cursor = cursors[id] ?? SessionCursor()
        if type == "session.replay_gap" {
            lastError = "Hermes is restoring this conversation after a stream gap."
            scheduleRefresh(resumeSession: true)
            return
        }
        if let epoch = event["replay_epoch"].string, let known = cursor.replayEpoch, epoch != known {
            scheduleRefresh(resumeSession: true)
            return
        }
        if let authority = event.object?["authority_epoch"], cursor.authorityEpoch != .null, authority != cursor.authorityEpoch {
            scheduleRefresh(resumeSession: true)
            return
        }
        if let sequence = event["seq"].int, sequence > cursor.sequence + 1 {
            scheduleRefresh(resumeSession: true)
            return
        }
        guard cursor.accept(event) else { return }
        cursors[id] = cursor
        let payload = event["payload"]
        let turn = event["admission_id"].string ?? "generation-\(cursor.generation)"
        let streamKey = "stream:\(id):\(turn)"
        let streamID = "\(streamKey):\(streamSegments[streamKey, default: 0])"
        let activityID = "activity:\(id):\(cursor.replayEpoch ?? ""):\(event["seq"].identifier ?? "\(cursor.generation):\(type)")"
        switch type {
        case "message.start":
            isStreaming = true
        case "message.delta":
            guard let delta = payload["text"].string else {
                sealSegment(streamID, key: streamKey)
                return
            }
            isStreaming = true
            let index = assistantIndex(id: streamID)
            messages[index].text += delta
        case "reasoning.delta", "thinking.delta":
            guard let delta = payload["text"].string else { return }
            messages[assistantIndex(id: streamID)].reasoning += delta
        case "reasoning.available":
            if let text = payload["text"].string { messages[assistantIndex(id: streamID)].reasoning = text }
        case "message.interim":
            let targetID = payload["already_streamed"].bool == true ? (sealedSegments[streamKey] ?? streamID) : streamID
            if let text = payload["text"].string {
                let projection = AttachmentProjection.extract(text)
                let index = assistantIndex(id: targetID)
                messages[index].text = projection.text
                messages[index].attachments = projection.attachments
            }
            if targetID == streamID { sealSegment(streamID, key: streamKey) }
        case "message.complete":
            let targetID = payload["response_reused"].bool == true ? (sealedSegments[streamKey] ?? streamID) : streamID
            let index = assistantIndex(id: targetID)
            if let finalText = payload["text"].string {
                let projection = AttachmentProjection.extract(finalText)
                messages[index].text = projection.text
                messages[index].attachments = projection.attachments
            }
            messages[index].status = payload["status"].string == "error" || !(payload["error"].string ?? "").isEmpty ? .failed : .complete
            isStreaming = false
            if let warning = payload["warning"].string, !warning.isEmpty { lastError = warning }
            if let error = payload["error"].string, !error.isEmpty { lastError = error }
            settleSubmission(payload["persisted_turn"], admissionID: event["admission_id"].string)
            scheduleRefresh()
        case "tool.start", "tool.generating":
            sealSegment(streamID, key: streamKey)
            let toolID = payload["tool_id"].identifier ?? "\(turn):\(payload["name"].string ?? "tool")"
            let messageID = "tool:\(id):\(toolID)"
            if !messages.contains(where: { $0.id == messageID }) {
                messages.append(ChatMessage(id: messageID, role: .tool,
                    text: payload["preview"].string ?? payload["args_text"].string ?? "Working…", status: .streaming,
                    toolName: payload["name"].string ?? "Tool"))
            }
        case "tool.progress", "tool.complete":
            guard let toolID = payload["tool_id"].identifier else { return }
            let messageID = "tool:\(id):\(toolID)"
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].text = payload["summary"].string ?? payload["result_text"].string ?? payload["message"].string ?? messages[index].text
                if type == "tool.complete" {
                    let projection = AttachmentProjection.extract(messages[index].text)
                    messages[index].text = projection.text
                    messages[index].attachments = projection.attachments
                    messages[index].status = .complete
                }
            }
        case "approval.request", "clarify.request": enqueuePrompt(payload, sessionID: id)
        case "approval.settled", "clarify.settled":
            if let promptID = payload["prompt_id"].string { interactions.removeAll { $0.id == promptID } }
            refreshPendingInteraction()
        case "request.cancel":
            if let requestID = payload["id"].identifier { interactions.removeAll { $0.id == "request:\(requestID)" } }
            refreshPendingInteraction()
        case "session.title":
            if let title = payload["title"].string {
                selectedThreadTitle = title
                if let index = threads.firstIndex(where: { $0.id == id }) { threads[index].title = title }
            }
        case "session.info":
            let previousModel = selectedModel
            applyInfo(payload)
            if !previousModel.isEmpty, !selectedModel.isEmpty, previousModel != selectedModel {
                let modelName = payload["model"].string ?? selectedModel
                let effort = selectedEffort.isEmpty ? "" : " · \(selectedEffort)"
                sealSegment(streamID, key: streamKey)
                appendActivity(id: activityID, text: "Model changed to \(modelName)\(effort)")
            }
        case "agent.print":
            if let text = payload["text"].string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sealSegment(streamID, key: streamKey)
                appendActivity(id: activityID, text: text)
            }
        case "status.update":
            if let running = payload["running"].bool { isStreaming = running }
            // The gateway tags actual compaction progress; never guess from arbitrary prose.
            if let kind = payload["kind"].string, ["compacting", "compacted", "compressing"].contains(kind),
               let text = payload["text"].string, !text.isEmpty {
                sealSegment(streamID, key: streamKey)
                appendActivity(id: activityID, text: text)
            }
        default: break // Additive gateway events are safe to ignore; cursor has advanced.
        }
    }

    func appendActivity(id: String, text: String) {
        guard !messages.contains(where: { $0.id == id }) else { return }
        messages.append(ChatMessage(id: id, role: .system, text: text, createdAt: Date()))
    }

    func assistantIndex(id: String) -> Int {
        if let index = messages.firstIndex(where: { $0.id == id }) { return index }
        messages.append(ChatMessage(id: id, role: .assistant, text: "", status: .streaming))
        return messages.count - 1
    }

    func sealSegment(_ id: String, key: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].status = .complete
        sealedSegments[key] = id
        streamSegments[key, default: 0] += 1
    }

    func settleSubmission(_ persisted: JSONValue, admissionID: String?) {
        let submissionID = persisted["submission_id"].string
        let completed = submissions.filter { submission in
            submission.sessionID == selectedThreadID && submission.profileID == profileID && submission.endpoint == credentials?.endpoint && submission.accountID == accountID &&
            ((submissionID != nil && submission.id == submissionID) || (admissionID != nil && submission.admissionID == admissionID))
        }
        guard !completed.isEmpty else { return }
        for submission in completed {
            if let index = messages.firstIndex(where: { $0.id == submission.id }) { messages[index].status = .complete }
        }
        let completedIDs = Set(completed.map(\.id))
        submissions.removeAll { completedIDs.contains($0.id) }
        do { try journal.save(submissions) } catch { report(error) }
    }

    func scheduleRefresh(resumeSession: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let self, self.connection == .connected else { return }
                if resumeSession, let id = self.selectedThreadID, !self.isLoadingMessages { try await self.resume(id) }
                await self.refreshThreads(query: self.threadSearchQuery)
            } catch is CancellationError { return }
            catch { self?.report(error) }
        }
    }

    func enqueuePrompt(_ payload: JSONValue, sessionID: String) {
        guard let id = payload["prompt_id"].string, !interactions.contains(where: { $0.id == id }) else { return }
        let approval = payload["kind"].string == "approval" || payload["command"].string != nil
        interactions.append(PendingInteraction(id: id, kind: approval ? .approval : .clarify,
            title: approval ? "Approval required" : "Hermes has a question",
            message: payload["question"].string ?? [payload["description"].string, payload["command"].string].compactMap { $0 }.joined(separator: "\n\n"),
            choices: payload["choices"].array?.compactMap(\.string) ?? [], sessionID: sessionID,
            generation: payload["execution_generation"].int, allowsMultipleSelection: payload["multi_select"].bool ?? false))
        refreshPendingInteraction()
    }

    func refreshPendingInteraction() { pendingInteraction = interactions.first { $0.sessionID == selectedThreadID } }

    func receiveServerRequest(_ request: GatewayEnvelope) {
        guard let rpcID = request.id, let method = request.method, let payload = request.params,
              let sessionID = payload["session_id"].string else { return }
        let id = "request:\(rpcID.identifier ?? UUID().uuidString)"
        guard !interactions.contains(where: { $0.id == id }) else { return }
        if method == "approval" {
            interactions.append(PendingInteraction(id: id, kind: .approval, title: "Approval required",
                message: [payload["description"].string, payload["command"].string].compactMap { $0 }.joined(separator: "\n\n"),
                choices: payload["choices"].array?.compactMap(\.string) ?? [], sessionID: sessionID, serverRequestID: rpcID))
        } else if method == "clarify", let questions = payload["questions"].array, let first = questions.first {
            let locked = payload["answers"].object ?? [:]
            let unanswered = questions.filter { locked[$0["qid"].string ?? ""] == nil }
            guard let question = unanswered.first else { return }
            interactions.append(PendingInteraction(id: id, kind: .clarify, title: "Hermes has a question",
                message: question["question"].string ?? first["question"].string ?? "", choices: question["choices"].array?.compactMap(\.string) ?? [],
                sessionID: sessionID, serverRequestID: rpcID, questionIDs: unanswered.compactMap { $0["qid"].string }, questions: unanswered, answers: locked,
                allowsMultipleSelection: question["multi_select"].bool ?? false))
        } else if ["sudo", "secret", "vault.unlock_prompt", "vault.code"].contains(method) {
            interactions.append(PendingInteraction(id: id, kind: .secret, title: "Secure input required",
                message: payload["prompt"].string ?? payload["message"].string ?? payload["command"].string ?? method,
                choices: [], isSensitive: true, sessionID: sessionID, serverRequestID: rpcID))
        } else {
            Task { [weak self] in
                do { try await self?.transport.respond(id: rpcID, result: .object(["value": .string("")])) }
                catch { self?.report(error) }
            }
            lastError = "Hermes requested an unsupported native capability (\(method)). The request was declined."
        }
        refreshPendingInteraction()
    }

    func restoreServerRequest(_ entry: JSONValue, sessionID: String) {
        guard let method = entry["method"].string, let id = entry.object?["id"] else { return }
        var params = entry["params"].object ?? [:]
        params["session_id"] = .string(sessionID)
        receiveServerRequest(GatewayEnvelope(id: id, method: method, params: .object(params)))
    }

    func respondToInteraction(_ answer: String) async {
        guard var interaction = pendingInteraction else { return }
        lastError = nil
        do {
            if let requestID = interaction.serverRequestID {
                if interaction.kind == .approval {
                    guard interaction.choices.contains(answer) else { throw GatewayError.invalidResponse("Choose one of the approval options supplied by Hermes.") }
                    try await transport.respond(id: requestID, result: .object(["choice": .string(answer)]))
                } else if interaction.kind == .clarify {
                    guard interaction.questionIndex < interaction.questionIDs.count else { return }
                    interaction.answers[interaction.questionIDs[interaction.questionIndex]] = .string(answer)
                    interaction.questionIndex += 1
                    if interaction.questionIndex < interaction.questions.count {
                        let next = interaction.questions[interaction.questionIndex]
                        interaction.message = next["question"].string ?? ""
                        interaction.choices = next["choices"].array?.compactMap(\.string) ?? []
                        interaction.allowsMultipleSelection = next["multi_select"].bool ?? false
                        if let index = interactions.firstIndex(where: { $0.id == interaction.id }) { interactions[index] = interaction }
                        refreshPendingInteraction()
                        return
                    }
                    try await transport.respond(id: requestID, result: .object(["answers": .object(interaction.answers), "outcome": .string("submitted")]))
                } else { try await transport.respond(id: requestID, result: .object(["value": .string(answer)])) }
            } else {
                guard let generation = interaction.generation else { throw GatewayError.invalidResponse("This question is missing its execution fence. Reopen the conversation.") }
                if interaction.kind == .approval, !interaction.choices.contains(answer) {
                    throw GatewayError.invalidResponse("Choose one of the approval options supplied by Hermes.")
                }
                var params: [String: JSONValue] = ["session_id": .string(interaction.sessionID), "execution_generation": .integer(generation), "prompt_id": .string(interaction.id)]
                params[interaction.kind == .approval ? "choice" : "answer"] = .string(answer)
                _ = try await transport.call(interaction.kind == .approval ? "approval.respond" : "clarify.respond", params: params)
            }
            interactions.removeAll { $0.id == interaction.id }
            refreshPendingInteraction()
        } catch { report(error) }
    }

    func respondToInteraction(_ answers: [String]) async {
        guard let interaction = pendingInteraction, interaction.allowsMultipleSelection else {
            lastError = "This question accepts one answer."
            return
        }
        do {
            // Matches apps/desktop/src/store/clarify.ts: multi-select answers are
            // JSON array strings inside the ordinary string-valued answer field.
            let data = try JSONEncoder().encode(answers)
            guard let answer = String(data: data, encoding: .utf8) else { throw GatewayError.invalidFrame }
            await respondToInteraction(answer)
        } catch { report(error) }
    }

    func cancelInteraction() async {
        guard let interaction = pendingInteraction else { return }
        if let requestID = interaction.serverRequestID, interaction.kind == .clarify {
            do {
                try await transport.respond(id: requestID, result: .object(["outcome": .string("cancelled")]))
                interactions.removeAll { $0.id == interaction.id }
                refreshPendingInteraction()
            } catch { report(error) }
        } else { await respondToInteraction(interaction.kind == .approval ? "deny" : "") }
    }
}
