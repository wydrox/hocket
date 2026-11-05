import Foundation

/// A server refusal to change models until its exact, revision-bound warning is accepted.
struct ModelSelectionConfirmation: Error, Identifiable, Sendable, Equatable, LocalizedError {
    let token: String
    let message: String
    var id: String { token }
    var errorDescription: String? { message }

    init?(_ result: JSONValue) {
        guard result["status"].string == "confirmation_required" || result["confirm_required"].bool == true else { return nil }
        token = result["confirm"].string ?? ""
        message = result["confirm_message"].string ?? "Hermes requires confirmation before changing this model."
    }
}
