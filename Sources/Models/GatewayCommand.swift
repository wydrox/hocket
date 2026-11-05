struct GatewayCommand: Identifiable, Codable, Sendable, Equatable {
    var id: String { name }
    var name: String
    var description: String
    var category: String = "Commands"
}
