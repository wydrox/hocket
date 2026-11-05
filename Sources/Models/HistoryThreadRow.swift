import Foundation

struct HistoryThreadRow: Sendable, Equatable {
    var thread: HermesThread
    var aliases: Set<String>

    init(_ row: JSONValue, canonical: Bool) throws {
        guard let id = (canonical ? row["session_id"].string ?? row["resolved_id"].string : nil) ?? row["id"].string,
              !id.isEmpty else {
            throw GatewayError.invalidResponse("Hermes returned a conversation without an identity. Try loading threads again.")
        }
        let title = row["title"].string ?? ""
        thread = HermesThread(id: id, title: title.isEmpty ? "Untitled conversation" : title,
            preview: row["preview"].string ?? "",
            updatedAt: HermesStore.date(row.object?["last_active"] ?? row.object?["updated_at"] ?? row["started_at"]),
            messageCount: Int(row["message_count"].int ?? 0), isRunning: row["running"].bool ?? false,
            isArchived: row["archived"].bool ?? false)
        aliases = Set([id, row["id"].string, row["session_id"].string, row["resolved_id"].string,
            row["_lineage_root_id"].string].compactMap { $0 }.filter { !$0.isEmpty })
        aliases.formUnion((row["_lineage_ids"].array ?? []).compactMap(\.string).filter { !$0.isEmpty })
        // A messaging chat_id is a delivery destination, not a conversation identity.
        if ["local", "cli", "tui", "gui", "desktop", "cron", "acp"].contains(row["source"].string ?? ""),
           let owner = row["chat_id"].string, !owner.isEmpty { aliases.insert(owner) }
    }

    init(thread: HermesThread, aliases: Set<String> = []) {
        self.thread = thread
        self.aliases = aliases.union([thread.id])
    }
}
