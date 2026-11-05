import Foundation
import Testing
@testable import HermesPocket

struct ProfileSelectionTests {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test func profileRosterDecodesOnlyPickerMetadataAndKeepsStableIdentity() throws {
        let roster = try HermesProfile.decodeRoster(json(#"{"profiles":[{"name":"research","display_name":"Research team","path":"/profiles/research","is_default":false,"last_session":{"id":"private-history"}},{"name":"default","path":"/hermes","is_default":true}]}"#))
        #expect(roster.map(\.id) == ["research", "default"])
        #expect(roster[0].title == "Research team")
        #expect(roster[1].title == "default")
        #expect(roster[1].isDefault)
    }

    @Test func malformedRosterCannotMasqueradeAsEmptySuccess() throws {
        for text in [#"{}"#, #"{"profiles":null}"#, #"{"profiles":[{"name":"x"}]}"#,
                     #"{"profiles":[{"name":"x","path":"/x"},{"name":"x","path":"/other"}]}"#,
                     #"{"profiles":[{"name":"x","path":"/x","display_name":9}]}"#,
                     #"{"profiles":[{"name":"x","path":"/x","is_default":"yes"}]}"#] {
            #expect(throws: (any Error).self) { try HermesProfile.decodeRoster(json(text)) }
        }
        #expect(try HermesProfile.decodeRoster(json(#"{"profiles":[]}"#)).isEmpty)
    }

    @Test func selectedAuthorityHomeMustBeVerifiedAndMatchRosterWhenKnown() throws {
        let response = try json(#"{"home":"/profiles/research","display":"/profiles/research"}"#)
        #expect(try HermesProfile.verifiedHome(response, expectedPath: "/profiles/research") == "/profiles/research")
        #expect(throws: (any Error).self) { try HermesProfile.verifiedHome(response, expectedPath: "/profiles/other") }
        #expect(throws: (any Error).self) { try HermesProfile.verifiedHome(.object([:])) }
    }

    @Test func scopedRequestsUseSelectedProfileWithoutChangingTheirPayload() {
        let params: [String: JSONValue] = ["session_id": .string("same-id"), "text": .string("message")]
        for method in ["session.list", "session.create", "session.resume", "session.info", "session.detach", "session.mutate",
                       "session.events.since", "session.interrupt", "prompt.submit", "prompt.receipt", "commands.catalog",
                       "command.dispatch", "model.options", "config.get", "config.set", "image.attach_bytes", "file.attach",
                       "approval.respond", "clarify.respond"] {
            let result = GatewayTransport.parameters(for: method, params: params, profileName: "research")
            #expect(result["profile"] == .string("research"))
            #expect(result["session_id"] == params["session_id"])
            #expect(result["text"] == params["text"])
        }
        #expect(GatewayTransport.parameters(for: "prompt.submit", params: params, profileName: nil) == params)
    }

    @Test func connectionMethodsAndDiscoveryRemainUnscoped() {
        for method in ["runtime.describe", "client.capabilities", "gateway.ping", "ping", "profiles.list", "unknown.future.method"] {
            #expect(GatewayTransport.parameters(for: method, params: [:], profileName: "research").isEmpty)
        }
    }

    @Test func oldCredentialsDecodeWithoutPreferenceAndNewPreferenceRoundTrips() throws {
        let old = Data(#"{"endpoint":"https://example.com","token":"example-token"}"#.utf8)
        var credentials = try JSONDecoder().decode(GatewayCredentials.self, from: old)
        #expect(credentials.profileName == nil)
        credentials.profileName = "research"
        let restored = try JSONDecoder().decode(GatewayCredentials.self, from: JSONEncoder().encode(credentials))
        #expect(restored == credentials)
        #expect(restored.profileName == "research")
    }

    @Test @MainActor func disconnectClearsTransportRouting() {
        let transport = GatewayTransport()
        transport.selectProfile("research")
        #expect(transport.profileName == "research")
        transport.disconnect()
        #expect(transport.profileName == nil)
    }

    @Test @MainActor func oldRosterCompletionCannotOverwriteNewConnection() async throws {
        let store = HermesStore()
        let fresh = try json(#"{"profiles":[{"name":"fresh","path":"/fresh"}]}"#)
        let obsolete = try json(#"{"profiles":[{"name":"obsolete","path":"/obsolete"}]}"#)
        await store.loadProfiles {
            store.connectionAttempt = UUID()
            await store.loadProfiles { fresh }
            return obsolete
        }
        #expect(store.profiles.map(\.name) == ["fresh"])
        #expect(!store.isLoadingProfiles)
        #expect(store.profileError == nil)
        await store.loadProfiles {
            store.connectionAttempt = UUID()
            await store.loadProfiles { fresh }
            throw GatewayError.timeout
        }
        #expect(store.profiles.map(\.name) == ["fresh"])
        #expect(store.profileError == nil)
        #expect(!store.isLoadingProfiles)
    }

    @Test @MainActor func profileTransitionSavesOldDraftAndFencesTransientState() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DraftJournal(directory: directory)
        let store = HermesStore(draftJournal: journal)
        let scope = DraftScope(endpoint: "https://example.com", accountID: "account", profileID: "/profiles/old")
        store.draftScope = scope
        store.activeDraftSessionID = "same-id"
        store.selectedThreadID = "same-id"
        store.composerText = "Keep this draft"
        store.isSending = true
        store.isUploadingAttachment = true
        store.isStreaming = true
        store.isLoadingMessages = true
        store.bufferedEvents = [.object(["session_id": .string("same-id")])]
        store.createRequestID = "old-create"
        let oldConnection = store.connectionAttempt
        let oldNavigation = store.navigationAttempt
        store.beginConnectionTransition()
        #expect(store.connectionAttempt != oldConnection)
        #expect(store.navigationAttempt != oldNavigation)
        #expect(store.selectedThreadID == nil)
        #expect(store.composerText.isEmpty)
        #expect(store.bufferedEvents.isEmpty)
        #expect(store.createRequestID == nil)
        #expect(!store.isSending && !store.isUploadingAttachment && !store.isStreaming && !store.isLoadingMessages)
        #expect(try journal.read(scope: scope).first?.text == "Keep this draft")
        #expect(throws: CancellationError.self) { try store.checkConnectionAttempt(oldConnection) }
    }

    @Test @MainActor func modelSettingsStopAtEachAwaitWhenProfileChanges() async {
        let stages = ["model", "reasoning", "config.set", "session.info"]
        for switchedAfter in stages {
            let store = HermesStore()
            store.selectedThreadID = "same-session-id"
            store.models = [ModelOption(id: "provider::desired", name: "desired", provider: "provider", supportsReasoning: true)]
            store.selectedModel = "current-profile-model"
            var operations: [String] = []
            @MainActor func finishOperation(_ name: String) async {
                operations.append(name)
                await Task.yield()
                if name == switchedAfter {
                    store.connectionAttempt = UUID()
                    // A different profile can contain the same session id.
                    store.selectedThreadID = "same-session-id"
                    store.lastError = "Current profile error"
                }
            }
            let result = await store.updateModelSettings(model: "provider::desired", effort: "high", tier: "normal",
                executeMutation: { _, operation, _ in await finishOperation(operation) },
                call: { method, _ in
                    await finishOperation(method)
                    return .object(["model": .string("obsolete-model"), "provider": .string("provider")])
                }, reloadCatalogs: { operations.append("reload") })
            let stop = stages.firstIndex(of: switchedAfter)!
            #expect(operations == Array(stages.prefix(stop + 1)))
            #expect(result == nil)
            #expect(store.selectedModel == "current-profile-model")
            #expect(store.lastError == "Current profile error")
        }
    }

    @Test @MainActor func oldSettingsFailureAndConfirmationDoNotPublishInNewProfile() async throws {
        let confirmation = try #require(ModelSelectionConfirmation(.object([
            "confirm_required": .bool(true), "confirm": .string("old-profile-token")
        ])))
        for requiresConfirmation in [false, true] {
            let store = HermesStore()
            store.selectedThreadID = "same-session-id"
            store.models = [ModelOption(id: "provider::desired", name: "desired", provider: "provider")]
            var followUps = 0
            let result = await store.updateModelSettings(model: "provider::desired", effort: "", tier: "normal",
                executeMutation: { _, _, _ in
                    await Task.yield()
                    store.connectionAttempt = UUID()
                    store.lastError = "Current profile error"
                    if requiresConfirmation { throw confirmation }
                    throw GatewayError.timeout
                }, call: { _, _ in followUps += 1; return .null },
                reloadCatalogs: { followUps += 1 })
            #expect(result == nil)
            #expect(followUps == 0)
            #expect(store.lastError == "Current profile error")
        }
    }

    @Test @MainActor func verifiedSettingsSequenceAppliesInfoAndReloadsCatalogs() async {
        let store = HermesStore()
        store.selectedThreadID = "session"
        store.models = [ModelOption(id: "provider::desired", name: "desired", provider: "provider", supportsReasoning: true)]
        var operations: [String] = []
        let result = await store.updateModelSettings(model: "provider::desired", effort: "high", tier: "normal",
            executeMutation: { _, operation, _ in operations.append(operation) },
            call: { method, _ in
                operations.append(method)
                return .object(["model": .string("desired"), "provider": .string("provider"),
                                "reasoning_effort": .string("high"), "service_tier": .string("normal")])
            }, reloadCatalogs: { operations.append("reload") })
        #expect(result == nil)
        #expect(operations == ["model", "reasoning", "config.set", "session.info", "reload"])
        #expect(store.selectedModel == "provider::desired")
        #expect(store.selectedEffort == "high")
        #expect(store.lastError == nil)
    }

}
