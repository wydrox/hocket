import Foundation
import Observation

@MainActor @Observable
final class HermesStore {
    var endpoint = ""
    var lastError: String?
    var threadListError: String?
    var commandWarning: String?
    var commandCatalogError: String?
    var modelCatalogError: String?
    var hasLoadedThreads = false
    var threadSearchQuery = ""
    var composerText = "" { didSet { composerDidChange() } }
    var selectedModel = ""
    var selectedEffort = ""
    var selectedServiceTier = "normal"
    var connection: ConnectionState = .disconnected
    var isRestoringConnection = true
    var hasCredentials = false
    var isLoadingThreads = false
    var isLoadingOlderThreads = false
    var hasOlderThreads = false
    var threadHistoryError: String?
    var profiles: [HermesProfile] = []
    var selectedProfileName: String?
    var profileError: String?
    var isLoadingProfiles = false
    var isSwitchingProfile = false
    var isLoadingMessages = false
    var isSending = false
    var isUploadingAttachment = false
    var threads: [HermesThread] = []
    var loadedConversationCount = 0
    var lastThreadsUpdatedAt: Date?
    var selectedThreadID: String?
    var selectedThreadTitle: String?
    var messages: [ChatMessage] = []
    var isStreaming = false
    var attachments: [ChatAttachment] = [] { didSet { composerDidChange() } }
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
    @ObservationIgnored let draftJournal: DraftJournal
    @ObservationIgnored var draftScope: DraftScope?
    @ObservationIgnored var activeDraftSessionID: String?
    @ObservationIgnored var isRestoringDraft = false
    @ObservationIgnored var draftSaveTask: Task<Void, Never>?
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
    @ObservationIgnored var threadHistory = ThreadHistoryState()
    @ObservationIgnored var profileRequestID = UUID()
    @ObservationIgnored var connectionAttempt = UUID()
    @ObservationIgnored var navigationAttempt = UUID()
    @ObservationIgnored var createRequestID: String?
    @ObservationIgnored var runtime: JSONValue = .null
    @ObservationIgnored var listRequestID = UUID()
    @ObservationIgnored var streamSegments: [String: Int] = [:]
    @ObservationIgnored var sealedSegments: [String: String] = [:]

    init(draftJournal: DraftJournal = DraftJournal()) {
        self.draftJournal = draftJournal
        transport.onEvent = { [weak self] event in self?.receiveEvent(event) }
        transport.onServerRequest = { [weak self] request in self?.receiveServerRequest(request) }
        transport.onDisconnect = { [weak self] message in
            guard let self else { return }
            guard self.connection == .connected || self.connection == .reconnecting else { return }
            self.lastError = message
            self.connection = .reconnecting
            self.scheduleReconnect()
        }
    }

    func restoreConnection() async {
        let attempt = connectionAttempt
        defer { if connectionAttempt == attempt { isRestoringConnection = false } }
        do {
            submissions = try journal.read()
            guard let saved = try keychain.read() else { return }
            hasCredentials = true
            endpoint = saved.endpoint
            credentials = saved
            selectedProfileName = saved.profileName
            connection = .connecting
            try await establish(saved, attempt: attempt)
        } catch {
            guard connectionAttempt == attempt else { return }
            transport.disconnect()
            connection = .disconnected
            report(error)
        }
    }

    func connect(endpoint: String, username: String, password: String, profileName: String? = nil) async {
        let attempt = beginConnectionTransition()
        profiles = []
        selectedProfileName = nil
        do {
            let address = try GatewayEndpoint(endpoint)
            var saved = try await NativeAuthentication().signIn(endpoint: address, username: username, password: password)
            try checkConnectionAttempt(attempt)
            saved.profileName = HermesProfile.normalizedName(profileName)
            try await establish(saved, attempt: attempt)
        } catch {
            guard connectionAttempt == attempt else { return }
            transport.disconnect()
            connection = .disconnected
            report(error)
        }
    }

    func connect(endpoint: String, token: String, profileName: String? = nil) async {
        let attempt = beginConnectionTransition()
        profiles = []
        selectedProfileName = nil
        do {
            let address = try GatewayEndpoint(endpoint)
            let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanToken.isEmpty else { throw GatewayError.emptyToken }
            let saved = GatewayCredentials(endpoint: address.origin.absoluteString, token: cleanToken,
                                           profileName: HermesProfile.normalizedName(profileName))
            try await establish(saved, attempt: attempt)
        } catch {
            guard connectionAttempt == attempt else { return }
            transport.disconnect()
            connection = .disconnected
            report(error)
        }
    }

    /// Fence every operation belonging to the old account/profile before opening a new socket.
    @discardableResult func beginConnectionTransition() -> UUID {
        saveDraft()
        connectionAttempt = UUID()
        reconnectTask?.cancel()
        refreshTask?.cancel()
        reconnectTask = nil
        refreshTask = nil
        transport.disconnect()
        clearSessionState()
        profileRequestID = UUID()
        isLoadingProfiles = false
        isSwitchingProfile = false
        isRestoringConnection = false
        lastError = nil
        profileError = nil
        connection = .connecting
        return connectionAttempt
    }

    func checkConnectionAttempt(_ attempt: UUID) throws {
        guard connectionAttempt == attempt, !Task.isCancelled else { throw CancellationError() }
    }

    func disconnect(forgetCredentials: Bool = false) async {
        connectionAttempt = UUID()
        navigationAttempt = UUID()
        listRequestID = UUID()
        profileRequestID = UUID()
        resetThreadHistory()
        isLoadingThreads = false
        isLoadingProfiles = false
        isSwitchingProfile = false
        isLoadingMessages = false
        isSending = false
        isUploadingAttachment = false
        bufferedEvents = []
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
                try forgetCurrentDrafts()
                try keychain.delete()
                credentials = nil
                hasCredentials = false
                endpoint = ""
                profiles = []
                selectedProfileName = nil
                profileError = nil
                clearSessionState()
            } catch { report(error) }
        }
    }

    func establish(_ saved: GatewayCredentials, attempt: UUID) async throws {
        try checkConnectionAttempt(attempt)
        var active = saved
        let selectedName = HermesProfile.normalizedName(active.profileName)
        if let expires = active.expiresAt, expires.timeIntervalSinceNow < 60, active.refreshToken != nil {
            active = try await refreshedCredentials(active)
            try checkConnectionAttempt(attempt)
            try preserveRefreshedAuthentication(active)
        }
        do {
            active.accountID = try await NativeAuthentication().accountIdentity(active)
            try checkConnectionAttempt(attempt)
            try await transport.connect(endpoint: GatewayEndpoint(active.endpoint), token: active.token)
        } catch GatewayError.authentication(401) where active.refreshToken != nil {
            try checkConnectionAttempt(attempt)
            active = try await refreshedCredentials(active)
            try checkConnectionAttempt(attempt)
            try preserveRefreshedAuthentication(active)
            active.accountID = try await NativeAuthentication().accountIdentity(active)
            try checkConnectionAttempt(attempt)
            try await transport.connect(endpoint: GatewayEndpoint(active.endpoint), token: active.token)
        }
        try checkConnectionAttempt(attempt)
        // runtime.describe has an empty param contract and describes the socket's launch authority.
        let described = try await transport.call("runtime.describe")
        try checkConnectionAttempt(attempt)
        guard let launchProfile = described["profile_id"].string, !launchProfile.isEmpty else {
            throw GatewayError.invalidResponse("Hermes did not identify its active profile.")
        }
        var roster: [HermesProfile] = []
        var rosterError: String?
        do {
            roster = try HermesProfile.decodeRoster(try await transport.call("profiles.list", params: ["include_sessions": .bool(false)]))
        } catch {
            try checkConnectionAttempt(attempt)
            if error is CancellationError { throw error }
            rosterError = error.localizedDescription
        }
        try checkConnectionAttempt(attempt)
        transport.selectProfile(selectedName)
        let verifiedProfile: String
        if let selectedName {
            let scope = try await transport.call("config.get", params: ["key": .string("profile")])
            try checkConnectionAttempt(attempt)
            verifiedProfile = try HermesProfile.verifiedHome(scope, expectedPath: roster.first(where: { $0.name == selectedName })?.path)
        } else {
            verifiedProfile = launchProfile
        }
        try checkConnectionAttempt(attempt)
        if accountID != (active.accountID ?? "") || profileID != verifiedProfile || credentials?.endpoint != active.endpoint {
            clearSessionState()
        }
        active.profileName = selectedName
        // A failed profile verification must never persist a fallback or an unverified preference.
        try keychain.save(active)
        credentials = active
        endpoint = active.endpoint
        hasCredentials = true
        accountID = active.accountID ?? ""
        profileID = verifiedProfile
        selectedProfileName = selectedName
        profiles = roster
        profileError = rosterError
        runtime = described
        try loadVerifiedDrafts()
        connection = .connected
        if let id = selectedThreadID {
            try await resume(id)
            try checkConnectionAttempt(attempt)
        }
        await refreshThreads(query: threadSearchQuery)
        try checkConnectionAttempt(attempt)
        await loadCatalogs()
        try checkConnectionAttempt(attempt)
    }

    private func refreshedCredentials(_ saved: GatewayCredentials) async throws -> GatewayCredentials {
        var refreshed = try await NativeAuthentication().refresh(saved)
        refreshed.profileName = saved.profileName
        refreshed.accountID = saved.accountID
        return refreshed
    }

    /// Keep rotated tokens even if a later profile read fails, retaining the last verified preference.
    private func preserveRefreshedAuthentication(_ refreshed: GatewayCredentials) throws {
        guard let previous = credentials, previous.endpoint == refreshed.endpoint,
              previous.accountID == refreshed.accountID else { return }
        var authentication = refreshed
        authentication.profileName = previous.profileName
        try keychain.save(authentication)
        credentials = authentication
    }

    func scheduleReconnect() {
        guard reconnectTask == nil, let saved = credentials else { return }
        let attempt = connectionAttempt
        reconnectTask = Task { [weak self] in
            defer { if self?.connectionAttempt == attempt { self?.reconnectTask = nil } }
            for delay in [1, 2, 4, 8, 16, 30] {
                do {
                    try await Task.sleep(for: .seconds(delay))
                    guard let self, self.connectionAttempt == attempt else { return }
                    try await self.establish(self.credentials ?? saved, attempt: attempt)
                    guard self.connectionAttempt == attempt else { return }
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

    func clearSessionState() {
        flushDrafts()
        navigationAttempt = UUID()
        profileRequestID = UUID()
        resetThreadHistory()
        isLoadingMessages = false
        isLoadingProfiles = false
        isSending = false
        isUploadingAttachment = false
        isStreaming = false
        bufferedEvents = []
        createRequestID = nil
        runtime = .null
        draftScope = nil
        activeDraftSessionID = nil
        isRestoringDraft = true
        defer { isRestoringDraft = false }
        selectedThreadID = nil
        selectedThreadTitle = nil
        messages = []
        threads = []
        loadedConversationCount = 0
        lastThreadsUpdatedAt = nil
        listRequestID = UUID()
        isLoadingThreads = false
        hasLoadedThreads = false
        threadSearchQuery = ""
        threadListError = nil
        commandWarning = nil
        commandCatalogError = nil
        modelCatalogError = nil
        drafts = [:]
        cursors = [:]
        interactions = []
        pendingInteraction = nil
        composerText = ""
        attachments = []
        models = []
        commands = []
        selectedModel = ""
        selectedEffort = ""
        selectedServiceTier = "normal"
        profileID = ""
        accountID = ""
        streamSegments = [:]
        sealedSegments = [:]
    }
}
