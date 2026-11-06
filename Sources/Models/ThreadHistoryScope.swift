import Foundation

struct ThreadHistoryScope: Equatable, Sendable {
    let endpoint: String?
    let account: String
    let profile: String
    let profileName: String?
}
