import Foundation

extension HermesStore {
    var currentProfileTitle: String {
        if let selectedProfileName {
            return profiles.first(where: { $0.name == selectedProfileName })?.title ?? selectedProfileName
        }
        return profiles.first(where: { $0.path == profileID })?.title ?? "Server default"
    }

    func refreshProfiles() async {
        guard connection == .connected else { return }
        await loadProfiles {
            try await self.transport.call("profiles.list", params: ["include_sessions": .bool(false)])
        }
    }

    /// The request and connection fences also protect failures from a previous profile/account.
    func loadProfiles(fetch: () async throws -> JSONValue) async {
        let attempt = connectionAttempt
        let request = UUID()
        profileRequestID = request
        isLoadingProfiles = true
        profileError = nil
        defer { if connectionAttempt == attempt, profileRequestID == request { isLoadingProfiles = false } }
        do {
            let response = try await fetch()
            guard connectionAttempt == attempt, profileRequestID == request, !Task.isCancelled else { return }
            profiles = try HermesProfile.decodeRoster(response)
        } catch {
            guard connectionAttempt == attempt, profileRequestID == request else { return }
            if !(error is CancellationError) { profileError = error.localizedDescription }
        }
    }

    func switchProfile(to name: String?) async {
        let name = HermesProfile.normalizedName(name)
        guard !isSwitchingProfile else { return }
        guard name != selectedProfileName || connection != .connected else { return }
        guard var saved = credentials else {
            profileError = "Connect to Hermes before choosing a profile."
            return
        }
        let previousName = selectedProfileName
        let attempt = beginConnectionTransition()
        isSwitchingProfile = true
        defer { if connectionAttempt == attempt { isSwitchingProfile = false } }
        saved.profileName = name
        do {
            try await establish(saved, attempt: attempt)
        } catch {
            guard connectionAttempt == attempt else { return }
            transport.disconnect()
            connection = .disconnected
            selectedProfileName = previousName
            if !(error is CancellationError) {
                profileError = "Could not open \(name ?? "the server default profile"): \(error.localizedDescription)"
            }
        }
    }
}
