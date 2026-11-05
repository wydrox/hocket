import Foundation
import Observation

@MainActor @Observable
final class HermesStore {
    var endpoint = ""
    var lastError: String?
    var composerText = ""
    var selectedModel = ""
    var selectedEffort = ""
    var selectedServiceTier = "normal"
    var connection: ConnectionState = .disconnected
    var isRestoringConnection = true
    var hasCredentials = false
    var isLoadingThreads = false
    var isLoadingMessages = false
    var isSending = false
    var isUploadingAttachment = false
    var threads: [HermesThread] = []
    var selectedThreadID: String?
    var messages: [ChatMessage] = []
    var isStreaming = false
    var attachments: [ChatAttachment] = []
    var commands: [GatewayCommand] = []
    var models: [ModelOption] = []
    var pendingInteraction: PendingInteraction?

    var supportsAttachments: Bool { connection == .connected && selectedThreadID != nil }
    var supportsThreadRename: Bool { connection == .connected }
    var supportsThreadArchive: Bool { connection == .connected }
    var supportsModelControls: Bool { connection == .connected && selectedThreadID != nil && !models.isEmpty }
    var supportsInterrupt: Bool { connection == .connected && selectedThreadID != nil }
    var availableEfforts: [String] {
        availableEfforts(for: selectedModel)
    }
    func availableEfforts(for modelID: String) -> [String] {
        guard let model = models.first(where: { $0.id == modelID }), model.supportsReasoning else { return [] }
        return (model.canDisableReasoning ? ["none"] : []) + ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
    }
    var availableServiceTiers: [String] {
        availableServiceTiers(for: selectedModel)
    }
    func availableServiceTiers(for modelID: String) -> [String] {
        guard let model = models.first(where: { $0.id == modelID }) else { return [] }
        return ["normal"] + (model.supportsFast ? ["priority"] : []) + (model.supportsUltraFast ? ["ultrafast"] : [])
    }

    @ObservationIgnored let transport = GatewayTransport()
    @ObservationIgnored let keychain = KeychainCredentials()
    @ObservationIgnored let journal = SubmissionJournal()
    @ObservationIgnored var credentials: GatewayCredentials?
    @ObservationIgnored var profileID = ""
    @ObservationIgnored var accountID = ""
    @ObservationIgnored var cursors: [String: SessionCursor] = [:]
    @ObservationIgnored var submissions: [PendingSubmission] = []
    @ObservationIgnored var drafts: [String: (text: String, attachments: [ChatAttachment])] = [:]
    @ObservationIgnored var interactions: [PendingInteraction] = []
    @ObservationIgnored var bufferedEvents: [JSONValue] = []
    @ObservationIgnored var reconnectTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var connectionAttempt = UUID()
    @ObservationIgnored var navigationAttempt = UUID()
    @ObservationIgnored var createRequestID: String?
    @ObservationIgnored var runtime: JSONValue = .null
    @ObservationIgnored var listRequestID = UUID()
    @ObservationIgnored var streamSegments: [String: Int] = [:]
    @ObservationIgnored var sealedSegments: [String: String] = [:]

    init() {
        transport.onEvent = { [weak self] event in self?.receiveEvent(event) }
        transport.onServerRequest = { [weak self] request in self?.receiveServerRequest(request) }
        transport.onDisconnect = { [weak self] message in
            guard let self else { return }
            self.lastError = message
            self.connection = .reconnecting
            self.scheduleReconnect()
        }
    }

    func restoreConnection() async {
        defer { isRestoringConnection = false }
        do {
            submissions = try journal.read()
            guard let saved = try keychain.read() else { return }
            hasCredentials = true
            endpoint = saved.endpoint
            credentials = saved
            connection = .connecting
            try await establish(saved, attempt: connectionAttempt)
        } catch {
            transport.disconnect()
            connection = .disconnected
            report(error)
        }
    }

    func connect(endpoint: String, username: String, password: String) async {
        lastError = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionAttempt = UUID()
        let attempt = connectionAttempt
        connection = .connecting
        do {
            let address = try GatewayEndpoint(endpoint)
            let saved = try await NativeAuthentication().signIn(endpoint: address, username: username, password: password)
            guard connectionAttempt == attempt else { return }
            saveDraft()
            clearSessionState()
            credentials = saved
            self.endpoint = saved.endpoint
            try keychain.save(credentials ?? saved)
            hasCredentials = true
            try await establish(saved, attempt: attempt)
        } catch {
            guard connectionAttempt == attempt else { return }
            transport.disconnect()
            connection = .disconnected
            report(error)
        }
    }

    func connect(endpoint: String, token: String) async {
        lastError = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        let attempt = UUID()
        connectionAttempt = attempt
        connection = .connecting
        do {
            let address = try GatewayEndpoint(endpoint)
            let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanToken.isEmpty else { throw GatewayError.emptyToken }
            saveDraft()
            clearSessionState()
            let saved = GatewayCredentials(endpoint: address.origin.absoluteString, token: cleanToken)
            credentials = saved
            self.endpoint = saved.endpoint
            try await establish(saved, attempt: attempt)
            try keychain.save(credentials ?? saved)
            hasCredentials = true
        } catch {
            guard connectionAttempt == attempt else { return }
            transport.disconnect()
            connection = .disconnected
            report(error)
        }
    }

    func disconnect(forgetCredentials: Bool = false) async {
        connectionAttempt = UUID()
        navigationAttempt = UUID()
        reconnectTask?.cancel()
        refreshTask?.cancel()
        reconnectTask = nil
        refreshTask = nil
        saveDraft()
        transport.disconnect()
        connection = .disconnected
        isStreaming = false
        if forgetCredentials {
            do {
                try keychain.delete()
                credentials = nil
                hasCredentials = false
                endpoint = ""
                clearSessionState()
            } catch { report(error) }
        }
    }

    func establish(_ saved: GatewayCredentials, attempt: UUID) async throws {
        var active = credentials ?? saved
        if let expires = active.expiresAt, expires.timeIntervalSinceNow < 60, active.refreshToken != nil {
            active = try await NativeAuthentication().refresh(active)
            try keychain.save(active)
            credentials = active
        }
        do {
            active.accountID = try await NativeAuthentication().accountIdentity(active)
            try await transport.connect(endpoint: GatewayEndpoint(active.endpoint), token: active.token)
        }
        catch GatewayError.authentication(401) where active.refreshToken != nil {
            active = try await NativeAuthentication().refresh(active)
            try keychain.save(active)
            credentials = active
            active.accountID = try await NativeAuthentication().accountIdentity(active)
            try await transport.connect(endpoint: GatewayEndpoint(active.endpoint), token: active.token)
        }
        guard connectionAttempt == attempt else { throw CancellationError() }
        if !accountID.isEmpty, accountID != active.accountID { clearSessionState() }
        credentials = active
        try keychain.save(active)
        runtime = try await transport.call("runtime.describe")
        guard let newProfile = runtime["profile_id"].string else {
            throw GatewayError.invalidResponse("Hermes did not identify its active profile.")
        }
        if !profileID.isEmpty, profileID != newProfile { clearSessionState() }
        accountID = active.accountID ?? ""
        profileID = newProfile
        connection = .connected
        if let id = selectedThreadID { try await resume(id) }
        try await loadThreads(query: "")
        await loadCatalogs()
    }

    func scheduleReconnect() {
        guard reconnectTask == nil, let saved = credentials else { return }
        let attempt = connectionAttempt
        reconnectTask = Task { [weak self] in
            defer { self?.reconnectTask = nil }
            for delay in [1, 2, 4, 8, 16, 30] {
                do {
                    try await Task.sleep(for: .seconds(delay))
                    guard let self, self.connectionAttempt == attempt else { return }
                    try await self.establish(saved, attempt: attempt)
                    self.lastError = nil
                    return
                } catch is CancellationError { return }
                catch {
                    guard let self, self.connectionAttempt == attempt else { return }
                    self.transport.disconnect()
                    self.connection = .reconnecting
                    self.report(error)
                }
            }
            guard let self, self.connectionAttempt == attempt else { return }
            self.connection = .disconnected
            self.lastError = "Hermes is still unreachable. Your unsent messages are saved; reconnect to retry."
        }
    }

    func report(_ error: any Error) {
        if error is CancellationError { return }
        if let urlError = error as? URLError {
            lastError = "Cannot reach Hermes securely (network error \(urlError.code.rawValue)). Check your connection and endpoint."
        } else { lastError = error.localizedDescription }
    }

    func saveDraft() {
        guard let id = selectedThreadID else { return }
        drafts[id] = (composerText, attachments)
    }

    func clearSessionState() {
        selectedThreadID = nil
        messages = []
        threads = []
        drafts = [:]
        cursors = [:]
        interactions = []
        pendingInteraction = nil
        composerText = ""
        attachments = []
        models = []
        commands = []
        profileID = ""
        accountID = ""
        streamSegments = [:]
        sealedSegments = [:]
    }
}
