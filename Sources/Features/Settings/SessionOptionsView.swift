import SwiftUI

struct SessionOptionsView: View {
    @Bindable var store: HermesStore
    @Environment(\.dismiss) private var dismiss
    @State private var model = ""
    @State private var provider = ""
    @State private var effort = ""
    @State private var serviceTier = ""
    @State private var isSaving = false

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
                    Button(isSaving ? "Saving…" : "Save Changes", action: save)
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
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        store.lastError = nil
        store.selectedModel = model
        store.selectedEffort = effort
        store.selectedServiceTier = serviceTier
        Task {
            await store.updateModelSettings()
            isSaving = false
            if store.lastError == nil { dismiss() }
        }
    }
}
