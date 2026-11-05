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
            let result = try await transport.call("commands.catalog", params: params)
            guard connectionAttempt == attempt, selectedThreadID == sessionID else { return }
            installCommandCatalog(result)
        } catch {
            guard connectionAttempt == attempt, selectedThreadID == sessionID else { return }
            if !(error is CancellationError) { commandCatalogError = error.localizedDescription }
        }
        do {
            let result = try await transport.call("model.options", params: params.merging(["explicit_only": .bool(false), "include_unconfigured": .bool(false), "refresh": .bool(false)]) { _, new in new })
            guard connectionAttempt == attempt, selectedThreadID == sessionID else { return }
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
            guard connectionAttempt == attempt, selectedThreadID == sessionID else { return }
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
        lastError = nil
        do {
            guard let id = selectedThreadID, let model = models.first(where: { $0.id == desiredModel }) else { throw GatewayError.missingSession }
            guard desiredEffort.isEmpty || availableEfforts(for: desiredModel).contains(desiredEffort) else { throw GatewayError.invalidResponse("This model does not advertise the selected reasoning option.") }
            guard availableServiceTiers(for: desiredModel).contains(desiredTier) else { throw GatewayError.invalidResponse("This model does not advertise the selected service tier.") }
            var payload: [String: JSONValue] = ["model": .string(model.name), "provider": .string(model.provider)]
            if !desiredEffort.isEmpty { payload["reasoning"] = .string(desiredEffort) }
            if let confirmation { payload["confirm"] = .string(confirmation) }
            try await mutate(id, operation: "model", payload: payload, requiresGeneration: true)
            if model.supportsReasoning {
                try await mutate(id, operation: "reasoning", payload: ["effort": desiredEffort.isEmpty ? .null : .string(desiredEffort)], requiresGeneration: true)
            }
            _ = try await transport.call("config.set", params: ["session_id": .string(id), "key": .string("service_tier"), "value": .string(desiredTier)])
            let info = try await transport.call("session.info", params: ["session_id": .string(id)])
            applyInfo(info)
            await loadCatalogs()
        } catch let guardrail as ModelSelectionConfirmation {
            guard !guardrail.token.isEmpty else {
                report(GatewayError.invalidResponse("Hermes requested model confirmation without a valid confirmation token. Refresh the session and try again."))
                return nil
            }
            return guardrail
        } catch { report(error) }
        return nil
    }
}
