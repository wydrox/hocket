import Foundation

struct HermesThread: Identifiable, Codable, Sendable, Equatable {
    let id: String
    var title: String
    var preview: String = ""
    var updatedAt: Date?
    var messageCount: Int = 0
    var isRunning: Bool = false
    var isArchived: Bool = false
}
