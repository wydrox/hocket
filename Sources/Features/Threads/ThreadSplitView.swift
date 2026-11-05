import SwiftUI

struct ThreadSplitView: View {
    @Bindable var store: HermesStore
    @Binding var showsSettings: Bool
    @State private var selection: String?
    @State private var search = ""
    @State private var isCreating = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ConnectionStatusView(connection: store.connection)
                    if store.isLoadingThreads { ProgressView("Loading Threads…") }
                    if store.connection != .connected {
                        Button("Reconnect", systemImage: "arrow.clockwise") {
                            Task { await store.restoreConnection() }
                        }
                        .frame(minHeight: 44)
                    }
                    if let error = store.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                        Button("Retry Loading Threads", systemImage: "arrow.clockwise") {
                            Task { await store.refreshThreads(query: search) }
                        }
                        .disabled(store.connection != .connected)
                    }
                }
                Section {
                    ForEach(store.threads) { thread in
                        NavigationLink(value: thread.id) { ThreadRow(thread: thread) }
                            .disabled(store.isLoadingMessages)
                    }
                }
            }
            .overlay {
                if store.threads.isEmpty, store.connection == .connected, !store.isLoadingThreads, store.lastError == nil {
                    ContentUnavailableView {
                        Label(search.isEmpty ? "No Threads Yet" : "No Matching Threads", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text(search.isEmpty ? "Start a conversation with Hermes." : "Try another word.")
                    } actions: {
                        if search.isEmpty { Button("New Thread", action: createThread).buttonStyle(.borderedProminent) }
                    }
                    .allowsHitTesting(search.isEmpty)
                }
            }
            .searchable(text: $search, prompt: "Search Threads")
            .task(id: search) {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard store.connection == .connected else { return }
                await store.refreshThreads(query: search)
            }
            .refreshable { await store.refreshThreads(query: search) }
            .navigationTitle("Threads")
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Thread", systemImage: "square.and.pencil", action: createThread)
                        .disabled(isCreating || store.connection != .connected)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                }
            }
        } detail: {
            NavigationStack {
                if store.selectedThreadID != nil {
                    ConversationView(store: store)
                } else {
                    ContentUnavailableView {
                        Label("Your Conversations", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Choose a thread or start a new conversation with Hermes.")
                    } actions: {
                        Button("New Thread", action: createThread)
                            .buttonStyle(.borderedProminent)
                            .disabled(store.connection != .connected || isCreating)
                    }
                    .navigationTitle("Hermes Pocket")
                }
            }
        }
        .onChange(of: selection) { _, id in
            guard let id, id != store.selectedThreadID else { return }
            Task { await store.openThread(id) }
        }
        .onChange(of: store.selectedThreadID) { _, id in selection = id }
        .onAppear { selection = store.selectedThreadID }
    }

    private func createThread() {
        guard !isCreating else { return }
        isCreating = true
        Task {
            await store.createThread()
            selection = store.selectedThreadID
            isCreating = false
        }
    }
}
