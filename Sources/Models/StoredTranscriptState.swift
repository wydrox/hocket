struct StoredTranscriptState: Sendable, Equatable {
    let selectionID: String
    let physicalID: String
    let profile: String
    let scope: ThreadHistoryScope
    var nextOffset: Int
}
