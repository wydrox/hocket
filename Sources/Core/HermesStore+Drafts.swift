import Foundation

extension HermesStore {
    /// Call synchronously on scene inactivity, before iOS suspends the application.
    func flushDrafts() {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        guard let scope = draftScope else { return }
        captureCurrentDraft()
        let records = drafts.map { id, value in
            ConversationDraft(scope: scope, sessionID: id, text: value.text, attachments: value.attachments)
        }
        do { try draftJournal.replace(scope: scope, drafts: records) }
        catch { report(error) }
    }

    func saveDraft() { flushDrafts() }

    func composerDidChange() {
        guard !isRestoringDraft, draftScope != nil, activeDraftSessionID != nil else { return }
        captureCurrentDraft()
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            self?.flushDrafts()
        }
    }

    func captureCurrentDraft() {
        guard !isRestoringDraft, draftScope != nil, let id = activeDraftSessionID else { return }
        if composerText.isEmpty, attachments.isEmpty { drafts.removeValue(forKey: id) }
        else { drafts[id] = (composerText, attachments) }
    }

    /// Called only after /api/auth/me and runtime.describe verify the current scope.
    func loadVerifiedDrafts() throws {
        guard let endpoint = credentials?.endpoint, !accountID.isEmpty, !profileID.isEmpty else { return }
        let scope = DraftScope(endpoint: endpoint, accountID: accountID, profileID: profileID)
        guard draftScope != scope else { return }
        flushDrafts()
        let records = try draftJournal.read(scope: scope)
        var restored: [String: (text: String, attachments: [ChatAttachment])] = [:]
        for record in records { restored[record.sessionID] = (record.text, record.attachments) }
        drafts = restored
        draftScope = scope
        activeDraftSessionID = nil
    }

    func activateDraft(sessionID: String) {
        guard activeDraftSessionID != sessionID else { return }
        flushDrafts()
        isRestoringDraft = true
        composerText = drafts[sessionID]?.text ?? ""
        attachments = drafts[sessionID]?.attachments ?? []
        activeDraftSessionID = sessionID
        isRestoringDraft = false
    }

    /// Acknowledgement clears only the exact draft sent, never newer typing or another account.
    func clearAcknowledgedDraft(scope: DraftScope?, sessionID: String, text: String, sentAttachments: [ChatAttachment]) {
        guard scope != nil, scope == draftScope else { return }
        captureCurrentDraft()
        guard let saved = drafts[sessionID], saved.text == text, saved.attachments == sentAttachments else { return }
        drafts.removeValue(forKey: sessionID)
        if activeDraftSessionID == sessionID {
            isRestoringDraft = true
            composerText = ""
            attachments = []
            isRestoringDraft = false
        }
        flushDrafts()
    }

    func forgetCurrentDrafts() throws {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        let endpoint = draftScope?.endpoint ?? credentials?.endpoint
        let account = draftScope?.accountID ?? credentials?.accountID
        guard let endpoint, let account, !account.isEmpty else { return }
        try draftJournal.removeConnection(endpoint: endpoint, accountID: account)
        // Clear the scope before session teardown so it cannot write the deleted drafts back.
        draftScope = nil
        activeDraftSessionID = nil
        drafts = [:]
    }
}
