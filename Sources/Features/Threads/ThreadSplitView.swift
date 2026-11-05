import SwiftUI

struct ThreadSplitView: View {
    @Bindable var store: HermesStore
    @Binding var showsSettings: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selection: String?
    @State private var search = ""
    @State private var isCreating = false
    @State private var showsProfiles = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    Button { showsProfiles = true } label: {
                        LabeledContent {
                            Text(store.currentProfileTitle)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label("Profile", systemImage: "person.crop.circle")
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Profile")
                    .accessibilityValue(store.currentProfileTitle)
                    .accessibilityHint("Choose a Hermes profile.")
                    .accessibilityIdentifier("threads.profile")
                    if store.isLoadingThreads { ProgressView("Loading Threads…") }
                    if store.connection != .connected {
                        Button("Reconnect", systemImage: "arrow.clockwise") {
                            Task { await store.restoreConnection() }
                        }
                        .frame(minHeight: 44)
                    }
                    if let error = store.threadListError {
                        Label("Couldn’t Refresh Threads", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                        if !store.threads.isEmpty {
                            Text("Your previous list is still available.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Details") { Text(error).font(.subheadline).textSelection(.enabled) }
                        Button("Retry Loading Threads", systemImage: "arrow.clockwise") {
                            Task { await store.refreshThreads(query: search) }
                        }
                        .disabled(store.connection != .connected || store.isLoadingThreads)
                    }
                }
                Section {
                    if store.threads.isEmpty, store.hasLoadedThreads, store.connection == .connected, !store.isLoadingThreads, store.threadListError == nil {
                        ContentUnavailableView {
                            Label(search.isEmpty ? "No Threads Yet" : "No Matching Threads", systemImage: "bubble.left.and.bubble.right")
                        } description: {
                            Text(search.isEmpty ? "Start a conversation with Hermes." : store.hasOlderThreads ? "Try another word or load older conversations." : "Try another word.")
                        } actions: {
                            if search.isEmpty { Button("New Thread", action: createThread).buttonStyle(.borderedProminent) }
                        }
                        .listRowBackground(Color.clear)
                    }
                    ForEach(store.threads) { thread in
                        NavigationLink(value: thread.id) { ThreadRow(thread: thread) }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .disabled(store.isLoadingMessages)
                    }
                }
                if store.hasOlderThreads || store.isLoadingOlderThreads || (store.threadHistoryError != nil && store.threadListError == nil) {
                    Section {
                        ThreadHistoryFooter(store: store)
                    } footer: {
                        if store.hasOlderThreads {
                            Text("Searches loaded conversations. Load older conversations to search more history.")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarConnectionFooter(store: store)
            }
            .searchable(text: $search, prompt: "Search Threads")
            .onChange(of: search) { store.setThreadSearchQuery(search) }
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
                    ConversationView(store: store, showsConnectionStatus: horizontalSizeClass != .regular || columnVisibility == .detailOnly)
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
                    .navigationTitle("hocket")
                }
            }
        }
        .onChange(of: selection) { _, id in
            guard let id, id != store.selectedThreadID else { return }
            Task { await store.openThread(id) }
        }
        .onChange(of: store.selectedThreadID) { _, id in selection = id }
        .onChange(of: store.threadSearchQuery) { _, query in search = query }
        .onAppear { selection = store.selectedThreadID; search = store.threadSearchQuery }
        .sheet(isPresented: $showsProfiles) { ProfilePickerView(store: store) }
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
