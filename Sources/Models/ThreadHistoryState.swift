import Foundation

struct ThreadHistoryState {
    var scope: ThreadHistoryScope?
    var rows: [HistoryThreadRow] = []
    var firstPageAliases: Set<String> = []
    var canonical: [HistoryThreadRow] = []
    var resumedAliases: [String: String] = [:]
    var nextOffset = 0
    var total = 0
}
