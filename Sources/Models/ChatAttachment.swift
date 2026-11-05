struct ChatAttachment: Identifiable, Codable, Sendable, Equatable {
    let id: String
    var name: String
    var mimeType: String
    var byteCount: Int
    var isImage: Bool
    var remotePath: String
    var referenceText: String?
}
