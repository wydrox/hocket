struct ModelOption: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var name: String
    var provider: String
    var supportsReasoning: Bool = false
    var supportsFast: Bool = false
    var supportsUltraFast: Bool = false
    var canDisableReasoning: Bool = false
}
