import Foundation
import Testing
@testable import HermesPocket

struct SessionReplayTests {
    @Test func snapshotInstallsFencesAndReplayDeduplicates() {
        var cursor = SessionCursor()
        cursor.installSnapshot(.object(["replay_epoch": .string("session-epoch"), "last_sequence": .integer(10), "revision": .integer(7), "execution_generation": .integer(2), "authority_epoch": .integer(1)]))
        let event: JSONValue = .object(["replay_epoch": .string("session-epoch"), "seq": .integer(11), "execution_generation": .integer(3), "authority_epoch": .integer(1)])
        let accepted = cursor.accept(event)
        let replayAccepted = cursor.accept(event)
        #expect(accepted)
        #expect(!replayAccepted)
        #expect(cursor.sequence == 11)
        #expect(cursor.generation == 3)
        #expect(cursor.revision == 7)
    }

    @Test func changedEpochRequiresSnapshotInsteadOfMixingStreams() {
        var cursor = SessionCursor(replayEpoch: "old", sequence: 50, authorityEpoch: .integer(1))
        let changedReplayAccepted = cursor.accept(.object(["replay_epoch": .string("new"), "seq": .integer(51)]))
        let changedAuthorityAccepted = cursor.accept(.object(["replay_epoch": .string("old"), "seq": .integer(51), "authority_epoch": .integer(2)]))
        #expect(!changedReplayAccepted)
        #expect(!changedAuthorityAccepted)
        #expect(cursor.sequence == 50)
    }

    @Test @MainActor func finalTextReplacesDeltasAndReplayedDeltaDoesNotDuplicate() async {
        let store = HermesStore()
        store.selectedThreadID = "session"
        store.cursors["session"] = SessionCursor(replayEpoch: "epoch", sequence: 0, generation: 1)
        let delta: JSONValue = .object(["type": .string("message.delta"), "session_id": .string("session"), "replay_epoch": .string("epoch"), "seq": .integer(1), "payload": .object(["text": .string("Hel")])])
        store.applyEvent(delta)
        store.applyEvent(delta)
        #expect(store.messages.count == 1)
        #expect(store.messages.first?.text == "Hel")
        store.applyEvent(.object(["type": .string("message.complete"), "session_id": .string("session"), "replay_epoch": .string("epoch"), "seq": .integer(2), "payload": .object(["text": .string("Hello")])]))
        #expect(store.messages.count == 1)
        #expect(store.messages.first?.text == "Hello")
        #expect(store.messages.first?.status == .complete)
        await store.disconnect()
    }

    @Test @MainActor func unknownEventAdvancesCursorWithoutInventingMessage() {
        let store = HermesStore()
        store.selectedThreadID = "session"
        store.cursors["session"] = SessionCursor(replayEpoch: "epoch", sequence: 7)
        store.applyEvent(.object(["type": .string("future.event"), "session_id": .string("session"), "replay_epoch": .string("epoch"), "seq": .integer(8), "payload": .object([:])]))
        #expect(store.cursors["session"]?.sequence == 8)
        #expect(store.messages.isEmpty)
    }
}
