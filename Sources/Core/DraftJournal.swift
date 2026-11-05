import Foundation

/// Stores composer content only. Credentials and interaction replies never enter this journal.
struct DraftJournal {
    private let url: URL

    init(directory: URL = URL.applicationSupportDirectory) {
        url = directory.appending(path: "HermesPocket", directoryHint: .isDirectory).appending(path: "conversation-drafts.json")
    }

    func read(scope: DraftScope) throws -> [ConversationDraft] {
        try readAll().filter { $0.scope == scope }
    }

    func replace(scope: DraftScope, drafts: [ConversationDraft]) throws {
        guard drafts.allSatisfy({ $0.scope == scope }) else {
            throw GatewayError.storage("Cannot save drafts under a different Hermes account.")
        }
        var records = try readAll().filter { $0.scope != scope }
        records.append(contentsOf: drafts.filter { !$0.text.isEmpty || !$0.attachments.isEmpty })
        try write(records)
    }

    func removeConnection(endpoint: String, accountID: String) throws {
        let records = try readAll().filter { $0.scope.endpoint != endpoint || $0.scope.accountID != accountID }
        try write(records)
    }

    private func readAll() throws -> [ConversationDraft] {
        guard FileManager.default.fileExists(atPath: url.path()) else { return [] }
        return try JSONDecoder().decode([ConversationDraft].self, from: Data(contentsOf: url))
    }

    private func write(_ records: [ConversationDraft]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }
}
