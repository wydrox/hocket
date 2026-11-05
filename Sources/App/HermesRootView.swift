import SwiftUI

struct HermesRootView: View {
    @State private var store = HermesStore()
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isRestoringConnection {
                ProgressView("Connecting to Hermes…")
            } else if !store.hasCredentials {
                NavigationStack {
                    ConnectionView(store: store, isInitialSetup: true)
                }
            } else {
                ThreadSplitView(store: store, showsSettings: $showsSettings)
            }
        }
        .task { await store.restoreConnection() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.hasCredentials, store.connection == .disconnected {
                Task { await store.restoreConnection() }
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack { SettingsView(store: store) }
        }
    }
}
