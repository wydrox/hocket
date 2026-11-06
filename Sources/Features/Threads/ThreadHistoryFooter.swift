import SwiftUI

struct ThreadHistoryFooter: View {
    @Bindable var store: HermesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isLoadingOlderThreads {
                ProgressView("Loading Older Conversations…")
                    .frame(minHeight: 44)
            } else {
                if let error = store.threadHistoryError {
                    Label("Couldn’t Load Older Conversations", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Text("Your loaded conversations are still available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("Details") { Text(error).font(.subheadline).textSelection(.enabled) }
                }
                if store.hasOlderThreads {
                    Button(store.threadHistoryError == nil ? "Load Older Conversations" : "Retry Loading Older Conversations", systemImage: "arrow.clockwise", action: loadOlder)
                        .frame(minHeight: 44)
                        .disabled(store.connection != .connected || store.isLoadingThreads || store.isSwitchingProfile)
                        .accessibilityIdentifier("threads.loadOlder")
                }
            }
        }
    }

    private func loadOlder() {
        Task { await store.loadOlderThreads() }
    }
}
