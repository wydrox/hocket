struct ConversationDraft: Codable, Sendable, Equatable {
    let scope: DraftScope
    let sessionID: String
    var text: String
    var attachments: [ChatAttachment]
}
