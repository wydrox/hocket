import Foundation

struct ThreadHistoryPage: Sendable {
    let rows: [HistoryThreadRow]
    let total: Int
    let limit: Int
    let offset: Int
    let isEmpty: Bool
    var nextOffset: Int { offset + limit }
    var hasMore: Bool { !isEmpty && nextOffset < total }

    init(_ result: JSONValue, expectedOffset: Int) throws {
        guard let sessions = result["sessions"].array,
              let total = result["total"].int, total >= 0, total <= Int64(Int.max),
              let limit = result["limit"].int, (1...100).contains(limit),
              let offset = result["offset"].int, offset >= 0, offset == Int64(expectedOffset),
              offset <= Int64(Int.max) - limit,
              let storage = result["storage"].object else {
            throw GatewayError.invalidResponse("Hermes returned an invalid conversation history page. Try loading it again.")
        }
        guard !storage.values.contains(where: { $0.string == "corrupt" }) else {
            throw GatewayError.invalidResponse("Hermes conversation storage is unavailable. Retry after the server store is repaired.")
        }
        rows = try sessions.filter { row in
            row["hidden"].bool != true && row["hidden"].int != 1 &&
                row["archived"].bool != true && row["archived"].int != 1 &&
                !["kanban", "tool", "oneshot", "subagent"].contains(row["source"].string ?? "")
        }.map { try HistoryThreadRow($0, canonical: false) }
        self.total = Int(total)
        self.limit = Int(limit)
        self.offset = Int(offset)
        isEmpty = sessions.isEmpty
    }
}
