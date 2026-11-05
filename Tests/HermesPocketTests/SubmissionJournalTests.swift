import Foundation
import Testing
@testable import HermesPocket

struct SubmissionJournalTests {
    @Test func persistenceKeepsRetryIdentityAndExactAttachmentPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SubmissionJournal(directory: directory)
        let attachment = ChatAttachment(id: "local-photo", name: "photo.png", mimeType: "image/png", byteCount: 128, isImage: true, remotePath: "/staged/photo.png")
        let submission = PendingSubmission(id: "same-durable-id", endpoint: "https://hermes.example", profileID: "profile", sessionID: "session", text: "Describe this", attachments: [attachment], createdAt: Date(timeIntervalSince1970: 1))
        try journal.save([submission])
        let restored = try #require(journal.read().first)
        #expect(restored == submission)
        #expect(restored.parameters == submission.parameters)
        #expect(restored.parameters["submission_id"] == .string("same-durable-id"))
        #expect(restored.parameters["attachments"] == .array([.object(["path": .string("/staged/photo.png"), "mime": .string("image/png")])]))
        #expect(restored.parameters["input_id"] == nil)
    }

    @Test func fileReferenceIsNotSentAsImageAttachment() {
        let file = ChatAttachment(id: "doc", name: "notes.pdf", mimeType: "application/pdf", byteCount: 128, isImage: false, remotePath: "/staged/notes.pdf", referenceText: "@file:/staged/notes.pdf")
        let submission = PendingSubmission(id: "durable", endpoint: "https://hermes.example", profileID: "profile", sessionID: "session", text: "Read\n\n@file:/staged/notes.pdf", attachments: [file], createdAt: .now)
        #expect(submission.parameters["attachments"] == nil)
        #expect(submission.parameters["text"] == .string("Read\n\n@file:/staged/notes.pdf"))
    }
}
