struct PendingInteraction: Identifiable, Codable, Sendable, Equatable {
    let id: String
    var kind: InteractionKind
    var title: String
    var message: String
    var choices: [String]
    var isSensitive: Bool = false
    var sessionID: String
    var generation: Int64?
    var serverRequestID: JSONValue?
    var questionIDs: [String] = []
    var questionIndex: Int = 0
    var questions: [JSONValue] = []
    var answers: [String: JSONValue] = [:]
    var allowsMultipleSelection: Bool = false
}
