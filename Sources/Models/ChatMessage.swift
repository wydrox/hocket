import Foundation

struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    let id: String
    var role: MessageRole
    var text: String
    var reasoning: String = ""
    var status: MessageStatus = .complete
    var createdAt: Date?
    var toolName: String?
    var attachments: [MessageAttachment] = []
}
