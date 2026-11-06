import SwiftUI

struct SettingsView: View {
    @Bindable var store: HermesStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsDisconnect = false
    @State private var showsProfiles = false

    private enum Destination: Hashable { case connection, help }

    var body: some View {
        Form {
            Section("Connection") {
                ConnectionStatusView(connection: store.connection)
                LabeledContent("Server") { Text(store.endpoint).textSelection(.enabled).multilineTextAlignment(.trailing) }
                Button { showsProfiles = true } label: {
                    LabeledContent("Profile") { Text(store.currentProfileTitle).multilineTextAlignment(.trailing) }
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Profile")
                .accessibilityValue(store.currentProfileTitle)
                .accessibilityIdentifier("settings.profile")
                NavigationLink("Edit Connection", value: Destination.connection)
                if store.connection != .connected {
                    Button("Reconnect", systemImage: "arrow.clockwise") { Task { await store.restoreConnection() } }
                }
                Button("Disconnect", role: .destructive) { showsDisconnect = true }
                    .confirmationDialog("Disconnect from Hermes?", isPresented: $showsDisconnect, titleVisibility: .visible) {
                        Button("Disconnect", role: .destructive) {
                            Task {
                                await store.disconnect(forgetCredentials: true)
                                dismiss()
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Removes the saved sign-in from this device. It won’t revoke your server token or delete conversations on the server.")
                    }
            }
            Section {
                NavigationLink("Help and Privacy", value: Destination.help)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
            } header: { Text("hocket") } footer: {
                Text("A native connection to your Hermes agent.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $showsProfiles) { ProfilePickerView(store: store) }
        .navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .connection: ConnectionView(store: store, isInitialSetup: false)
            case .help: HelpView()
            }
        }
    }
}
