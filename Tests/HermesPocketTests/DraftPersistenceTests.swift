import Foundation
import Testing
@testable import HermesPocket

struct DraftPersistenceTests {
    private let endpoint = "https://hermes.example"

    @Test @MainActor func restartRestoresOnlyExactVerifiedAccountProfileAndThread() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DraftJournal(directory: directory)
        let first = try store(journal: journal, account: "alice", profile: "work")
        first.activateDraft(sessionID: "thread")
        first.composerText = "An unsent thought"
        first.attachments = [ChatAttachment(id: "pdf", name: "notes.pdf", mimeType: "application/pdf", byteCount: 12, isImage: false, remotePath: "/staged/notes.pdf", referenceText: "@file:/staged/notes.pdf")]
        first.flushDrafts()

        let restarted = try store(journal: journal, account: "alice", profile: "work")
        restarted.activateDraft(sessionID: "thread")
        #expect(restarted.composerText == "An unsent thought")
        #expect(restarted.attachments.first?.name == "notes.pdf")
        restarted.activateDraft(sessionID: "different-thread")
        #expect(restarted.composerText.isEmpty)
        restarted.flushDrafts()

        let otherAccount = try store(journal: journal, account: "bob", profile: "work")
        otherAccount.activateDraft(sessionID: "thread")
        #expect(otherAccount.composerText.isEmpty)
        let otherProfile = try store(journal: journal, account: "alice", profile: "personal")
        otherProfile.activateDraft(sessionID: "thread")
        #expect(otherProfile.composerText.isEmpty)
        let otherEndpoint = DraftScope(endpoint: "https://another.example", accountID: "alice", profileID: "work")
        #expect(try journal.read(scope: otherEndpoint).isEmpty)
    }

    @Test @MainActor func snapshotNavigationDoesNotSaveOldComposerIntoNewThread() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DraftJournal(directory: directory)
        let state = try store(journal: journal, account: "alice", profile: "work")
        state.activateDraft(sessionID: "first")
        state.composerText = "Belongs to first"
        state.selectedThreadID = "second" // Simulate selection changing ahead of projection restoration.
        state.activateDraft(sessionID: "second")
        state.composerText = "Belongs to second"
        state.flushDrafts()
        let records = try journal.read(scope: DraftScope(endpoint: endpoint, accountID: "alice", profileID: "work"))
        #expect(records.first(where: { $0.sessionID == "first" })?.text == "Belongs to first")
        #expect(records.first(where: { $0.sessionID == "second" })?.text == "Belongs to second")
    }

    @Test @MainActor func acknowledgementDeletesExactDraftButPreservesNewTyping() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DraftJournal(directory: directory)
        let state = try store(journal: journal, account: "alice", profile: "work")
        state.activateDraft(sessionID: "thread")
        state.composerText = "sent text"
        state.flushDrafts()
        let scope = try #require(state.draftScope)
        state.composerText = "new typing while sending"
        state.clearAcknowledgedDraft(scope: scope, sessionID: "thread", text: "sent text", sentAttachments: [])
        #expect(state.composerText == "new typing while sending")
        state.clearAcknowledgedDraft(scope: scope, sessionID: "thread", text: "new typing while sending", sentAttachments: [])
        #expect(state.composerText.isEmpty)
        #expect(try journal.read(scope: scope).isEmpty)
    }

    @Test func forgettingConnectionPreservesOtherAccountsAndEndpoints() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DraftJournal(directory: directory)
        let scopes = [DraftScope(endpoint: endpoint, accountID: "alice", profileID: "work"),
            DraftScope(endpoint: endpoint, accountID: "alice", profileID: "personal"),
            DraftScope(endpoint: endpoint, accountID: "bob", profileID: "work"),
            DraftScope(endpoint: "https://other.example", accountID: "alice", profileID: "work")]
        for scope in scopes { try journal.replace(scope: scope, drafts: [ConversationDraft(scope: scope, sessionID: "thread", text: "draft", attachments: [])]) }
        try journal.removeConnection(endpoint: endpoint, accountID: "alice")
        #expect(try journal.read(scope: scopes[0]).isEmpty)
        #expect(try journal.read(scope: scopes[1]).isEmpty)
        #expect(try journal.read(scope: scopes[2]).count == 1)
        #expect(try journal.read(scope: scopes[3]).count == 1)
    }

    @MainActor private func store(journal: DraftJournal, account: String, profile: String) throws -> HermesStore {
        let state = HermesStore(draftJournal: journal)
        state.credentials = GatewayCredentials(endpoint: endpoint, token: "fixture-token", accountID: account)
        state.accountID = account
        state.profileID = profile
        try state.loadVerifiedDrafts()
        return state
    }
}
