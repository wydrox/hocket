import SwiftUI

struct CommandDetailView: View {
    @Bindable var store: HermesStore
    let command: GatewayCommand
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var arguments = ""
    @State private var isRunning = false

    var body: some View {
        Form {
            Section {
                Text(command.name).font(.headline)
                if !command.description.isEmpty { Text(command.description) }
            }
            Section("Arguments") {
                TextField("Arguments, if needed", text: $arguments, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Text("Runs in the current conversation on your Hermes server. Review the command and arguments before continuing.")
                    .foregroundStyle(.secondary)
                Button(isRunning ? "Running…" : "Run Command", systemImage: "play") { run() }
                    .frame(minHeight: 44)
                    .disabled(isRunning || store.connection != .connected)
            }
            if let error = store.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Run Command")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isRunning) }
        }
        .interactiveDismissDisabled(isRunning)
        .onAppear {
            let components = store.composerText.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            if let enteredName = components.first,
               String(enteredName).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == command.name.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
               components.count > 1 {
                arguments = String(components[1])
            }
        }
    }

    private func run() {
        guard !isRunning else { return }
        isRunning = true
        store.lastError = nil
        let original = store.composerText
        Task {
            await store.runCommand(command, arguments: arguments)
            isRunning = false
            if store.lastError == nil {
                let entered = original.split(maxSplits: 1, whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                if entered.hasPrefix("/"), entered.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == command.name.trimmingCharacters(in: CharacterSet(charactersIn: "/")), store.composerText == original {
                    store.composerText = ""
                }
                completed()
            }
        }
    }
}
