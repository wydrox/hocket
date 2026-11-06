import SwiftUI

struct ProfilePickerView: View {
    @Bindable var store: HermesStore
    @Environment(\.dismiss) private var dismiss
    @State private var isSelecting = false
    @State private var isRefreshing = false

    private var isBusy: Bool { isSelecting || isRefreshing || store.isSwitchingProfile || store.isLoadingProfiles }
    private var orderedProfiles: [HermesProfile] {
        store.profiles.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Current Profile") {
                        Text(store.currentProfileTitle).multilineTextAlignment(.trailing)
                    }
                    if isSelecting || store.isSwitchingProfile {
                        ProgressView("Opening Profile…")
                    }
                } footer: {
                    Text("Choose which Hermes profile’s conversations to open.")
                }
                Section {
                    Button { choose(nil) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Server Default")
                                Text("Use the profile chosen by this server.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.selectedProfileName == nil {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Server Default")
                    .accessibilityValue(store.selectedProfileName == nil ? "Current profile" : "")
                    .accessibilityAddTraits(store.selectedProfileName == nil ? [.isSelected] : [])
                    .accessibilityIdentifier("profiles.serverDefault")
                    .disabled(isBusy)
                }
                Section("Profiles") {
                    ForEach(orderedProfiles) { profile in
                        Button { choose(profile.name) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.title)
                                    if profile.title != profile.name {
                                        Text(profile.name).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if store.selectedProfileName == profile.name {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel(profile.title)
                        .accessibilityValue(store.selectedProfileName == profile.name ? "Current profile" : "")
                        .accessibilityAddTraits(store.selectedProfileName == profile.name ? [.isSelected] : [])
                        .accessibilityIdentifier("profiles.\(profile.name)")
                        .disabled(isBusy)
                    }
                    if store.isLoadingProfiles {
                        ProgressView("Loading Profiles…").frame(minHeight: 44)
                    } else if store.profiles.isEmpty && store.profileError == nil {
                        Text("No named profiles are available. You can use the server default.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = store.profileError {
                    Section {
                        Label("Couldn’t Open Profiles", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(error).font(.subheadline).textSelection(.enabled)
                        Text("Your previous profile is still selected.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if store.connection == .connected {
                            Button("Retry Loading Profiles", systemImage: "arrow.clockwise", action: refresh)
                                .frame(minHeight: 44)
                                .disabled(isBusy)
                        } else {
                            Button("Reconnect", systemImage: "arrow.clockwise", action: reconnect)
                                .frame(minHeight: 44)
                                .disabled(isBusy)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSelecting || store.isSwitchingProfile)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh Profiles", systemImage: "arrow.clockwise", action: refresh)
                        .disabled(isBusy || store.connection != .connected)
                }
            }
            .task {
                guard store.profiles.isEmpty, store.profileError == nil, !isBusy, store.connection == .connected else { return }
                await store.refreshProfiles()
            }
        }
        .interactiveDismissDisabled(isSelecting || store.isSwitchingProfile)
        .accessibilityIdentifier("profiles.picker")
    }

    private func choose(_ name: String?) {
        guard !isBusy else { return }
        isSelecting = true
        Task {
            await store.switchProfile(to: name)
            isSelecting = false
            if store.connection == .connected, store.selectedProfileName == name {
                dismiss()
            }
        }
    }

    private func refresh() {
        guard !isBusy, store.connection == .connected else { return }
        isRefreshing = true
        Task {
            await store.refreshProfiles()
            isRefreshing = false
        }
    }

    private func reconnect() {
        guard !isBusy else { return }
        isSelecting = true
        Task {
            await store.restoreConnection()
            isSelecting = false
        }
    }
}
