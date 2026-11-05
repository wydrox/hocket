import Foundation

extension HermesStore {
    func loadCatalogs() async {
        let attempt = connectionAttempt
        let sessionID = selectedThreadID
        commandCatalogError = nil
        modelCatalogError = nil
        var params: [String: JSONValue] = [:]
        if let id = selectedThreadID { params["session_id"] = .string(id) }
        do {
            try checkConnectionAttempt(attempt)
            let result = try await transport.call("commands.catalog", params: params)
            guard connectionAttempt == attempt, selectedThreadID == sessionID, !Task.isCancelled else { return }
            installCommandCatalog(result)
        } catch {
            guard connectionAttempt == attempt, selectedThreadID == sessionID, !Task.isCancelled else { return }
            if !(error is CancellationError) { commandCatalogError = error.localizedDescription }
        }
        do {
            try checkConnectionAttempt(attempt)
            let result = try await transport.call("model.options", params: params.merging(["explicit_only": .bool(false), "include_unconfigured": .bool(false), "refresh": .bool(false)]) { _, new in new })
            guard connectionAttempt == attempt, selectedThreadID == sessionID, !Task.isCancelled else { return }
            models = (result["providers"].array ?? []).flatMap { provider -> [ModelOption] in
                guard provider["authenticated"].bool != false, let slug = provider["slug"].string else { return [] }
                return (provider["models"].array ?? []).compactMap { value in
                    guard let model = value.string else { return nil }
                    let capabilities = provider["capabilities"][model]
                    return ModelOption(id: "\(slug)::\(model)", name: model, provider: slug,
                        supportsReasoning: capabilities["reasoning"].bool ?? false,
                        supportsFast: capabilities["fast"].bool ?? false, supportsUltraFast: capabilities["ultrafast"].bool ?? false,
                        canDisableReasoning: capabilities["can_disable_reasoning"].bool ?? false)
                }
            }
            if let current = result["model"].string, let provider = result["provider"].string { selectedModel = "\(provider)::\(current)" }
        } catch {
            guard connectionAttempt == attempt, selectedThreadID == sessionID, !Task.isCancelled else { return }
            if !(error is CancellationError) { modelCatalogError = error.localizedDescription }
        }
    }

    func installCommandCatalog(_ result: JSONValue) {
        var catalog: [String: GatewayCommand] = [:]
        for category in result["categories"].array ?? [] {
            for pair in category["pairs"].array ?? [] {
                guard let values = pair.array, let name = values.first?.string else { continue }
                catalog[name] = GatewayCommand(name: name, description: values.dropFirst().first?.string ?? "", category: category["name"].string ?? "Commands")
            }
        }
        for pair in result["pairs"].array ?? [] {
            guard let values = pair.array, let name = values.first?.string, catalog[name] == nil else { continue }
            catalog[name] = GatewayCommand(name: name, description: values.dropFirst().first?.string ?? "")
        }
        commands = catalog.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        commandWarning = result["warning"].string.flatMap { $0.isEmpty ? nil : $0 }
    }

    func applyInfo(_ info: JSONValue) {
        if let model = info["model"].string {
            if let provider = info["provider"].string { selectedModel = "\(provider)::\(model)" }
            else if let option = models.first(where: { $0.name == model }) { selectedModel = option.id }
        }
        selectedEffort = info["reasoning_effort"].string ?? ""
        selectedServiceTier = info["service_tier"].string ?? "normal"
    }

    func updateModelSettings(model desiredModel: String, effort desiredEffort: String, tier desiredTier: String, confirmation: String? = nil) async -> ModelSelectionConfirmation? {
        await updateModelSettings(model: desiredModel, effort: desiredEffort, tier: desiredTier, confirmation: confirmation,
            executeMutation: { id, operation, payload in
                try await self.mutate(id, operation: operation, payload: payload, requiresGeneration: true)
            }, call: { method, params in
                try await self.transport.call(method, params: params)
            }, reloadCatalogs: { await self.loadCatalogs() })
    }

    /// Keep the complete settings operation in its original connection and conversation.
    /// The injected operations exercise the same sequencing without a server or credentials.
    func updateModelSettings(model desiredModel: String, effort desiredEffort: String, tier desiredTier: String, confirmation: String? = nil,
                             executeMutation: (String, String, [String: JSONValue]) async throws -> Void,
                             call: (String, [String: JSONValue]) async throws -> JSONValue,
                             reloadCatalogs: () async -> Void) async -> ModelSelectionConfirmation? {
        let attempt = connectionAttempt
        let sessionID = selectedThreadID
        lastError = nil
        @MainActor func checkScope() throws {
            try checkConnectionAttempt(attempt)
            guard selectedThreadID == sessionID else { throw CancellationError() }
        }
        do {
            try checkScope()
            guard let id = sessionID, let model = models.first(where: { $0.id == desiredModel }) else { throw GatewayError.missingSession }
            guard desiredEffort.isEmpty || availableEfforts(for: desiredModel).contains(desiredEffort) else { throw GatewayError.invalidResponse("This model does not advertise the selected reasoning option.") }
            guard availableServiceTiers(for: desiredModel).contains(desiredTier) else { throw GatewayError.invalidResponse("This model does not advertise the selected service tier.") }
            var payload: [String: JSONValue] = ["model": .string(model.name), "provider": .string(model.provider)]
            if !desiredEffort.isEmpty { payload["reasoning"] = .string(desiredEffort) }
            if let confirmation { payload["confirm"] = .string(confirmation) }
            try await executeMutation(id, "model", payload)
            try checkScope()
            if model.supportsReasoning {
                try await executeMutation(id, "reasoning", ["effort": desiredEffort.isEmpty ? .null : .string(desiredEffort)])
                try checkScope()
            }
            _ = try await call("config.set", ["session_id": .string(id), "key": .string("service_tier"), "value": .string(desiredTier)])
            try checkScope()
            let info = try await call("session.info", ["session_id": .string(id)])
            try checkScope()
            applyInfo(info)
            await reloadCatalogs()
            try checkScope()
        } catch let guardrail as ModelSelectionConfirmation {
            guard connectionAttempt == attempt, selectedThreadID == sessionID, !Task.isCancelled else { return nil }
            guard !guardrail.token.isEmpty else {
                report(GatewayError.invalidResponse("Hermes requested model confirmation without a valid confirmation token. Refresh the session and try again."))
                return nil
            }
            return guardrail
        } catch {
            guard connectionAttempt == attempt, selectedThreadID == sessionID, !Task.isCancelled else { return nil }
            report(error)
        }
        return nil
    }
}
