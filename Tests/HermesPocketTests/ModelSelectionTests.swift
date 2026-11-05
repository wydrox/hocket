import Testing
@testable import HermesPocket

struct ModelSelectionTests {
    @Test func confirmationRefusalPreservesExactServerTokenAndWarning() throws {
        let value: JSONValue = .object(["status": .string("confirmation_required"), "confirm": .string("revision-bound-token"),
            "confirm_message": .string("This model has a higher cost."), "target_model": .string("example-model")])
        let confirmation = try #require(ModelSelectionConfirmation(value))
        #expect(confirmation.token == "revision-bound-token")
        #expect(confirmation.message == "This model has a higher cost.")
    }

    @Test func successfulMutationDoesNotAskForConfirmation() {
        #expect(ModelSelectionConfirmation(.object(["revision": .integer(5)])) == nil)
    }

    @Test func malformedConfirmationRemainsARefusal() throws {
        let confirmation = try #require(ModelSelectionConfirmation(.object(["confirm_required": .bool(true)])))
        #expect(confirmation.token.isEmpty)
    }
}
