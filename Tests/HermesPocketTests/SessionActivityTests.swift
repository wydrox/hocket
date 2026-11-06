import Foundation
import Testing
@testable import HermesPocket

struct SessionActivityTests {
    @MainActor private func store() -> HermesStore {
        let store = HermesStore()
        store.selectedThreadID = "session"
        store.cursors["session"] = SessionCursor(replayEpoch: "epoch", sequence: 0)
        return store
    }

    private func event(_ type: String, sequence: Int64, payload: [String: JSONValue]) -> JSONValue {
        .object(["type": .string(type), "session_id": .string("session"), "replay_epoch": .string("epoch"),
                 "seq": .integer(sequence), "payload": .object(payload)])
    }

    @Test @MainActor func liveModelInfoUpdatesControlsAndAddsOneTimelineEntry() {
        let store = store()
        store.selectedModel = "provider::previous"
        let info = event("session.info", sequence: 1, payload: ["provider": .string("provider"), "model": .string("current"), "reasoning_effort": .string("high")])
        store.applyEvent(info)
        store.applyEvent(info)
        #expect(store.selectedModel == "provider::current")
        #expect(store.selectedEffort == "high")
        #expect(store.messages.count == 1)
        #expect(store.messages.first?.role == .system)
        #expect(store.messages.first?.text == "Model changed to current · high")
        store.applyEvent(event("session.info", sequence: 2, payload: ["provider": .string("provider"), "model": .string("current")]))
        #expect(store.messages.count == 1)
    }

    @Test @MainActor func compactionAndAgentNoticesAreScopedTimelineEntries() {
        let store = store()
        store.applyEvent(event("status.update", sequence: 1, payload: ["kind": .string("compacting"), "text": .string("Summarizing context…")]))
        store.applyEvent(event("agent.print", sequence: 2, payload: ["text": .string("Context compression complete")]))
        #expect(store.messages.map(\.text) == ["Summarizing context…", "Context compression complete"])
        #expect(store.messages.allSatisfy { $0.role == .system })
        #expect(store.lastError == nil)
        #expect(store.threadListError == nil)
        store.applyEvent(event("status.update", sequence: 3, payload: ["kind": .string("status"), "text": .string("Ready")]))
        #expect(store.messages.count == 2)
    }

    @Test @MainActor func generatedTitleSurvivesSelectedThreadBeingAbsentFromSearchResults() {
        let store = store()
        store.threads = []
        store.applyEvent(event("session.title", sequence: 1, payload: ["title": .string("Generated title")]))
        #expect(store.selectedThreadTitle == "Generated title")
        #expect(store.threads.isEmpty)
    }

    @Test @MainActor func toolActivitySeparatesAssistantSegmentsInTranscriptOrder() {
        let store = store()
        store.applyEvent(event("message.delta", sequence: 1, payload: ["text": .string("I’ll check.")]))
        store.applyEvent(event("tool.start", sequence: 2, payload: ["tool_id": .string("tool-1"), "name": .string("session.list")]))
        store.applyEvent(event("tool.complete", sequence: 3, payload: ["tool_id": .string("tool-1"), "summary": .string("3 conversations")]))
        store.applyEvent(event("message.delta", sequence: 4, payload: ["text": .string("Found three conversations.")]))
        #expect(store.messages.map(\.role) == [.assistant, .tool, .assistant])
        #expect(store.messages.map(\.text) == ["I’ll check.", "3 conversations", "Found three conversations."])
        #expect(store.messages[0].status == .complete)
        #expect(store.messages[1].status == .complete)
    }

    @Test @MainActor func systemActivityStaysBetweenAssistantSegments() {
        let store = store()
        store.applyEvent(event("message.delta", sequence: 1, payload: ["text": .string("Before compaction")]))
        store.applyEvent(event("status.update", sequence: 2, payload: ["kind": .string("compacting"), "text": .string("Summarizing context…")]))
        store.applyEvent(event("message.delta", sequence: 3, payload: ["text": .string("After compaction")]))
        #expect(store.messages.map(\.role) == [.assistant, .system, .assistant])
        #expect(store.messages.map(\.text) == ["Before compaction", "Summarizing context…", "After compaction"])
    }
}
