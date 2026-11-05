import SwiftUI

struct CommandsView: View {
    @Bindable var store: HermesStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var commands: [GatewayCommand] {
        guard !search.isEmpty else { return store.commands }
        return store.commands.filter { $0.name.localizedStandardContains(search) || $0.description.localizedStandardContains(search) }
    }

    var body: some View {
        List(commands) { command in
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
        .overlay {
            if commands.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No Commands Available" : "No Matching Commands", systemImage: "slash.circle", description: Text(search.isEmpty ? "This server hasn’t provided a command list." : "Try another word."))
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
}
