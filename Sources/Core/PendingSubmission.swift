import Foundation

struct PendingSubmission: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let endpoint: String
    let profileID: String
    let sessionID: String
    let text: String
    let attachments: [ChatAttachment]
    let createdAt: Date
    var admissionID: String?
    var accountID: String?

    var parameters: [String: JSONValue] {
        var result: [String: JSONValue] = ["session_id": .string(sessionID), "submission_id": .string(id), "text": .string(text)]
        let images = attachments.filter(\.isImage).map { JSONValue.object(["path": .string($0.remotePath), "mime": .string($0.mimeType)]) }
        if !images.isEmpty { result["attachments"] = .array(images) }
        return result
    }
}
