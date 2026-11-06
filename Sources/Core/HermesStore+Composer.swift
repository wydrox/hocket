import Foundation

extension HermesStore {
    func sendMessage() async {
        guard !isReadOnlyConversation else { report(GatewayError.invalidResponse("This saved conversation is read-only through this connection.")); return }
        guard !isSending, !isUploadingAttachment else { return }
        let attempt = connectionAttempt
        lastError = nil
        let draft = composerText
        let selectedAttachments = attachments
        let sentScope = draftScope
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedAttachments.isEmpty else { return }
        isSending = true
        saveDraft()
        defer { if connectionAttempt == attempt { isSending = false } }
        do {
            guard let sessionID = selectedThreadID, let credentials else { throw GatewayError.missingSession }
            let references = selectedAttachments.compactMap(\.referenceText)
            let text = ([draft] + references).filter { !$0.isEmpty }.joined(separator: "\n\n")
            if let existing = submissions.last(where: { candidate in candidate.sessionID == sessionID && candidate.endpoint == credentials.endpoint &&
                candidate.profileID == profileID && candidate.accountID == accountID && candidate.text == text && candidate.attachments == selectedAttachments &&
                messages.contains(where: { $0.id == candidate.id && $0.status == .failed }) }) {
                try await submit(existing)
                try checkConnectionAttempt(attempt)
                clearAcknowledgedDraft(scope: sentScope, sessionID: sessionID, text: draft, sentAttachments: selectedAttachments)
                return
            }
            let submission = PendingSubmission(id: UUID().uuidString, endpoint: credentials.endpoint, profileID: profileID,
                sessionID: sessionID, text: text, attachments: selectedAttachments, createdAt: .now, accountID: accountID)
            // Persist identity before touching the network. A lost ACK must not create a new turn.
            submissions.append(submission)
            do { try journal.save(submissions) }
            catch { submissions.removeAll { $0.id == submission.id }; throw error }
            messages.append(ChatMessage(id: submission.id, role: .user, text: draft, status: .pending, createdAt: submission.createdAt,
                attachments: selectedAttachments.map(MessageAttachment.staged)))
            try await submit(submission)
            try checkConnectionAttempt(attempt)
            clearAcknowledgedDraft(scope: sentScope, sessionID: sessionID, text: draft, sentAttachments: selectedAttachments)
        } catch { if connectionAttempt == attempt { report(error) } }
    }

    func retryMessage(_ id: String) async {
        guard !isReadOnlyConversation else { report(GatewayError.invalidResponse("This saved conversation is read-only through this connection.")); return }
        guard !isSending else { return }
        let attempt = connectionAttempt
        lastError = nil
        isSending = true
        defer { if connectionAttempt == attempt { isSending = false } }
        do {
            guard let submission = submissions.first(where: { $0.id == id }), submission.profileID == profileID,
                  submission.endpoint == credentials?.endpoint, submission.accountID == accountID else { throw GatewayError.invalidResponse("This message belongs to another saved Hermes connection.") }
            let sentScope = draftScope
            try await submit(submission)
            try checkConnectionAttempt(attempt)
            if let draft = drafts[submission.sessionID], draft.attachments == submission.attachments {
                let submittedText = ([draft.text] + draft.attachments.compactMap(\.referenceText)).filter { !$0.isEmpty }.joined(separator: "\n\n")
                if submittedText == submission.text {
                    clearAcknowledgedDraft(scope: sentScope, sessionID: submission.sessionID, text: draft.text, sentAttachments: draft.attachments)
                }
            }
        } catch { if connectionAttempt == attempt { report(error) } }
    }

    func submit(_ submission: PendingSubmission) async throws {
        try requireWritableConversation()
        let attempt = connectionAttempt
        guard submission.endpoint == credentials?.endpoint, submission.accountID == accountID,
              submission.profileID == profileID else { throw CancellationError() }
        do {
            try checkConnectionAttempt(attempt)
            let receipt = try await transport.call("prompt.submit", params: submission.parameters, timeout: .seconds(45))
            try checkConnectionAttempt(attempt)
            guard let admission = receipt["admission_id"].string else { throw GatewayError.invalidResponse("Hermes did not return a durable prompt receipt. Retry this same message.") }
            if let index = submissions.firstIndex(where: { $0.id == submission.id }) { submissions[index].admissionID = admission }
            try journal.save(submissions)
            if let index = messages.firstIndex(where: { $0.id == submission.id }) { messages[index].status = .pending }
            if let generation = receipt["execution_generation"].int { cursors[submission.sessionID]?.generation = generation }
            if receipt["status"].string == "unknown" {
                throw GatewayError.invalidResponse("Hermes lost the execution state of this accepted message. It has not been resubmitted; resolve it on the server before continuing.")
            }
            if receipt["status"].string == "terminal" {
                if let index = messages.firstIndex(where: { $0.id == submission.id }) { messages[index].status = .complete }
                if selectedThreadID == submission.sessionID {
                    try checkConnectionAttempt(attempt)
                    try await resume(submission.sessionID)
                    try checkConnectionAttempt(attempt)
                }
            } else { isStreaming = receipt["status"].string == "started" || isStreaming }
        } catch {
            if connectionAttempt == attempt, let index = messages.firstIndex(where: { $0.id == submission.id }) { messages[index].status = .failed }
            throw error
        }
    }

    func interrupt() async {
        let attempt = connectionAttempt
        lastError = nil
        do {
            try requireWritableConversation()
            guard let id = selectedThreadID, let cursor = cursors[id] else { throw GatewayError.missingSession }
            _ = try await transport.call("session.interrupt", params: ["session_id": .string(id), "execution_generation": .integer(cursor.generation)])
            try checkConnectionAttempt(attempt)
            try await resume(id)
            try checkConnectionAttempt(attempt)
        } catch { if connectionAttempt == attempt { report(error) } }
    }

    func addAttachment(data: Data, name: String, mimeType: String) async {
        guard !isReadOnlyConversation else { report(GatewayError.invalidResponse("This saved conversation is read-only through this connection.")); return }
        let attempt = connectionAttempt
        lastError = nil
        guard !isUploadingAttachment else { return }
        isUploadingAttachment = true
        defer { if connectionAttempt == attempt { isUploadingAttachment = false } }
        do {
            guard let id = selectedThreadID else { throw GatewayError.missingSession }
            let uploadScope = draftScope
            guard attachments.count < 10 else { throw GatewayError.invalidResponse("Attach at most 10 files to one message.") }
            guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else { throw GatewayError.invalidResponse("Choose a nonempty file no larger than 16 MiB.") }
            let supportedImages = ["image/png", "image/jpeg", "image/gif", "image/webp"]
            let isImage = supportedImages.contains(mimeType)
            if mimeType.hasPrefix("image/"), !isImage {
                throw GatewayError.invalidResponse("Hermes accepts PNG, JPEG, GIF, and WebP images. Export this image in one of those formats first.")
            }
            let result: JSONValue
            if isImage {
                result = try await transport.call("image.attach_bytes", params: ["session_id": .string(id), "content_base64": .string(data.base64EncodedString()), "filename": .string(name)], timeout: .seconds(60))
            } else {
                result = try await transport.call("file.attach", params: ["session_id": .string(id), "data_url": .string("data:\(mimeType);base64,\(data.base64EncodedString())"), "name": .string(name)], timeout: .seconds(60))
            }
            try checkConnectionAttempt(attempt)
            guard result["attached"].bool == true, let path = result["path"].string else { throw GatewayError.invalidResponse("Hermes did not confirm attachment staging.") }
            guard uploadScope != nil, uploadScope == draftScope else { throw GatewayError.invalidResponse("The attachment was staged for the previous connection. Select it again in the current account.") }
            let attachment = ChatAttachment(id: UUID().uuidString, name: name, mimeType: result["mime"].string ?? mimeType,
                byteCount: data.count, isImage: isImage, remotePath: path, referenceText: result["ref_text"].string)
            if !isImage, attachment.referenceText == nil { throw GatewayError.invalidResponse("Hermes did not return the staged file reference.") }
            if selectedThreadID == id { attachments.append(attachment); saveDraft() }
            else { var draft = drafts[id] ?? (text: "", attachments: []); draft.attachments.append(attachment); drafts[id] = draft; flushDrafts() }
        } catch { if connectionAttempt == attempt { report(error) } }
    }

    func removeAttachment(_ id: String) { attachments.removeAll { $0.id == id }; saveDraft() }

    func runCommand(_ command: GatewayCommand, arguments: String = "") async {
        let attempt = connectionAttempt
        lastError = nil
        do {
            try requireWritableConversation()
            guard let id = selectedThreadID else { throw GatewayError.missingSession }
            var name = command.name.hasPrefix("/") ? String(command.name.dropFirst()) : command.name
            for _ in 0..<5 {
                try checkConnectionAttempt(attempt)
                let result = try await transport.call("command.dispatch", params: ["session_id": .string(id), "name": .string(name), "arg": .string(arguments)])
                try checkConnectionAttempt(attempt)
                switch result["type"].string {
                case "exec", "plugin":
                    messages.append(ChatMessage(id: "command:\(UUID().uuidString)", role: .system, text: result["output"].string ?? result["notice"].string ?? "Command completed."))
                    return
                case "prefill":
                    let prefill = result["message"].string ?? ""
                    let invocation = ([command.name.hasPrefix("/") ? command.name : "/\(command.name)", arguments]).filter { !$0.isEmpty }.joined(separator: " ")
                    if composerText.isEmpty || composerText == invocation { composerText = prefill }
                    else { composerText += "\n\n" + prefill }
                    saveDraft()
                    return
                case "send", "skill":
                    guard let text = result["message"].string, let credentials else { throw GatewayError.invalidResponse("Hermes returned an empty command directive.") }
                    let submission = PendingSubmission(id: UUID().uuidString, endpoint: credentials.endpoint, profileID: profileID, sessionID: id, text: text, attachments: [], createdAt: .now, accountID: accountID)
                    submissions.append(submission)
                    try journal.save(submissions)
                    messages.append(ChatMessage(id: submission.id, role: .user, text: result["display"].string ?? command.name, status: .pending))
                    try await submit(submission)
                    try checkConnectionAttempt(attempt)
                    return
                case "alias":
                    guard let target = result["target"].string, !target.isEmpty else { throw GatewayError.invalidResponse("Hermes returned an invalid command alias.") }
                    name = target.hasPrefix("/") ? String(target.dropFirst()) : target
                default: throw GatewayError.invalidResponse("Hermes returned an unsupported command directive.")
                }
            }
            throw GatewayError.invalidResponse("Hermes returned a command alias loop.")
        } catch { if connectionAttempt == attempt { report(error) } }
    }
}
