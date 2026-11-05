struct SessionCursor: Codable, Sendable, Equatable {
    var replayEpoch: String?
    var sequence: Int64 = 0
    var revision: Int64 = 0
    var generation: Int64 = 0
    var authorityEpoch: JSONValue = .null
    var subscriptionID: String?

    mutating func installSnapshot(_ snapshot: JSONValue) {
        replayEpoch = snapshot["replay_epoch"].string
        sequence = snapshot["last_sequence"].int ?? 0
        revision = snapshot["revision"].int ?? revision
        generation = snapshot["execution_generation"].int ?? generation
        authorityEpoch = snapshot["authority_epoch"]
        subscriptionID = snapshot["subscription_id"].string
    }

    /// Epoch changes require a snapshot; unknown events still advance an accepted cursor.
    mutating func accept(_ event: JSONValue) -> Bool {
        if let epoch = event["replay_epoch"].string, let replayEpoch, epoch != replayEpoch { return false }
        if let incomingAuthority = event.object?["authority_epoch"], authorityEpoch != .null, incomingAuthority != authorityEpoch { return false }
        if let seq = event["seq"].int {
            guard seq > sequence else { return false }
            sequence = seq
        }
        if let next = event["execution_generation"].int { generation = max(generation, next) }
        return true
    }
}
