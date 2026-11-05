import SwiftUI

struct CommandsView: View {
    @Bindable var store: HermesStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var isRefreshing = false

    private var commands: [GatewayCommand] {
        guard !search.isEmpty else { return store.commands }
        return store.commands.filter { $0.name.localizedStandardContains(search) || $0.description.localizedStandardContains(search) }
    }

    private var hasPlanAliasNotice: Bool {
        guard let warning = store.commandWarning else { return false }
        let mentionsPlan = warning.localizedStandardContains("/plan") && warning.localizedStandardContains("/skill plan")
        let mentionsBuiltIn = warning.localizedStandardContains("built-in") || warning.localizedStandardContains("built in")
        return mentionsPlan && mentionsBuiltIn
    }

    var body: some View {
        List {
            if let warning = store.commandWarning {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(hasPlanAliasNotice ? "Command Alias Needs Attention" : "Command Notice", systemImage: "info.circle")
                            .font(.headline)
                        if hasPlanAliasNotice {
                            Text("To run the planning skill, use /skill plan. The built-in /plan command remains available.")
                                .font(.subheadline)
                            Button("Use /skill plan", systemImage: "text.insert") { prefillPlanSkill() }
                                .frame(minHeight: 44)
                        } else {
                            Text("Hermes provided a notice for its command catalog.")
                                .font(.subheadline)
                        }
                        DisclosureGroup("Details") {
                            Text(warning).font(.subheadline).textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if let error = store.commandCatalogError {
                Section {
                    Label("Couldn’t Refresh Commands", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    if !store.commands.isEmpty {
                        Text("The previous command list is still available.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Details") { Text(error).font(.subheadline).textSelection(.enabled) }
                    Button(isRefreshing ? "Refreshing…" : "Retry Loading Commands", systemImage: "arrow.clockwise") { refreshCommands() }
                        .frame(minHeight: 44)
                        .disabled(isRefreshing || store.connection != .connected)
                }
            }
            Section {
                ForEach(commands) { command in
                    NavigationLink(value: command.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(command.name).font(.headline)
                            if !command.description.isEmpty {
                                Text(command.description).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if commands.isEmpty, store.commandCatalogError == nil {
                    ContentUnavailableView(search.isEmpty ? "No Commands Available" : "No Matching Commands", systemImage: "slash.circle", description: Text(search.isEmpty ? "This server hasn’t provided a command list." : "Try another word."))
                }
            }
        }
        .searchable(text: $search, prompt: "Search Commands")
        .navigationTitle("Commands")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .navigationDestination(for: String.self) { id in
            if let command = store.commands.first(where: { $0.id == id }) {
                CommandDetailView(store: store, command: command) { dismiss() }
            }
        }
        .onAppear {
            if store.composerText.hasPrefix("/") {
                search = String(store.composerText.dropFirst()).components(separatedBy: .whitespacesAndNewlines).first ?? ""
            }
        }
    }

    private func prefillPlanSkill() {
        let draft = store.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isEmpty || draft == "/plan" || draft == "/skill plan" {
            store.composerText = "/skill plan "
        } else if draft.hasPrefix("/plan ") {
            store.composerText = "/skill plan " + String(draft.dropFirst("/plan ".count))
        } else {
            store.composerText = "/skill plan " + store.composerText
        }
        dismiss()
    }

    private func refreshCommands() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await store.loadCatalogs()
            isRefreshing = false
        }
    }
}
