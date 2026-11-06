import SwiftUI

struct SessionOptionsView: View {
    @Bindable var store: HermesStore
    @Environment(\.dismiss) private var dismiss
    @State private var model = ""
    @State private var provider = ""
    @State private var effort = ""
    @State private var serviceTier = ""
    @State private var isSaving = false
    @State private var isRefreshingModels = false
    @State private var modelConfirmation: ModelSelectionConfirmation?

    private var providers: [String] { Set(store.models.map(\.provider)).sorted() }
    private var filteredModels: [ModelOption] { store.models.filter { provider.isEmpty || $0.provider == provider } }
    private var efforts: [String] { store.availableEfforts(for: model) }
    private var tiers: [String] { store.availableServiceTiers(for: model) }

    var body: some View {
        Form {
            Section {
                Text("Options are provided by your Hermes server.")
                    .foregroundStyle(.secondary)
            }
            if let error = store.modelCatalogError {
                Section {
                    Label("Couldn’t Refresh Models", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    if !store.models.isEmpty {
                        Text("The previous model list is still available.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Details") { Text(error).font(.subheadline).textSelection(.enabled) }
                    Button(isRefreshingModels ? "Refreshing…" : "Retry Loading Models", systemImage: "arrow.clockwise") { refreshModels() }
                        .frame(minHeight: 44)
                        .disabled(isRefreshingModels || isSaving || store.connection != .connected)
                }
            }
            if store.supportsModelControls {
                if !store.models.isEmpty {
                    Section("Model") {
                        Picker("Provider", selection: $provider) {
                            Text("All Providers").tag("")
                            ForEach(providers, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Model", selection: $model) {
                            ForEach(filteredModels) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                    }
                }
                if !efforts.isEmpty {
                    Section("Reasoning Effort") {
                        Picker("Reasoning Effort", selection: $effort) {
                            Text("Server Default").tag("")
                            ForEach(efforts, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                if !tiers.isEmpty {
                    Section("Service Tier") {
                        Picker("Service Tier", selection: $serviceTier) {
                            ForEach(tiers, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            } else {
                Section {
                    Text("This server doesn’t expose session options.")
                    if !store.selectedModel.isEmpty { LabeledContent("Current Model", value: store.selectedModel) }
                }
            }
            if let error = store.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Session Options")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
            if store.supportsModelControls {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save Changes") { save() }
                        .disabled(isSaving || store.connection != .connected || !store.models.contains(where: { $0.id == model }))
                }
            }
        }
        .onAppear {
            model = store.selectedModel
            provider = store.models.first { $0.id == model }?.provider ?? ""
            effort = store.selectedEffort
            serviceTier = store.selectedServiceTier
        }
        .onChange(of: provider) { _, value in
            if !value.isEmpty, store.models.first(where: { $0.id == model })?.provider != value {
                model = store.models.first(where: { $0.provider == value })?.id ?? ""
            }
        }
        .onChange(of: model) { _, _ in
            if !effort.isEmpty, !efforts.contains(effort) { effort = "" }
            if !tiers.contains(serviceTier) { serviceTier = tiers.first ?? "" }
        }
        .interactiveDismissDisabled(isSaving)
        .alert("Review Model Change", isPresented: Binding(
            get: { modelConfirmation != nil },
            set: { if !$0 { modelConfirmation = nil } }
        ), presenting: modelConfirmation) { confirmation in
            Button("Cancel", role: .cancel) { }
            Button("Change Model") { save(confirmation: confirmation.token) }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private func refreshModels() {
        guard !isRefreshingModels else { return }
        isRefreshingModels = true
        Task {
            await store.loadCatalogs()
            isRefreshingModels = false
            if model.isEmpty {
                model = store.selectedModel
                provider = store.models.first { $0.id == model }?.provider ?? ""
            }
        }
    }

    private func save(confirmation: String? = nil) {
        guard !isSaving else { return }
        isSaving = true
        store.lastError = nil
        Task {
            modelConfirmation = await store.updateModelSettings(model: model, effort: effort, tier: serviceTier, confirmation: confirmation)
            isSaving = false
            if store.lastError == nil, modelConfirmation == nil { dismiss() }
        }
    }
}
