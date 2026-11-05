import SwiftUI

struct ConversationView: View {
    @Bindable var store: HermesStore
    @State private var showsCommands = false
    @State private var showsSession = false
    @State private var showsRename = false
    @State private var showsArchiveConfirmation = false
    @State private var newTitle = ""
    @State private var followsEnd = true
    @State private var isUserScrolling = false
    @State private var hasNewContent = false

    private var thread: HermesThread? { store.threads.first { $0.id == store.selectedThreadID } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ConnectionStatusView(connection: store.connection, isStreaming: store.isStreaming)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let error = store.lastError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                            HStack {
                                if store.connection != .connected {
                                    Button("Reconnect", systemImage: "arrow.clockwise") { Task { await store.restoreConnection() } }
                                }
                                Button("Dismiss") { store.lastError = nil }
                            }
                            .frame(minHeight: 44)
                        }
                        .padding(12)
                        .background(.quaternary, in: .rect(cornerRadius: 12))
                    }
                    if store.connection != .connected, store.isStreaming {
                        Label("Connection interrupted. Reconnect to check the response before sending again.", systemImage: "wifi.slash")
                            .font(.subheadline)
                    }
                    if store.isLoadingMessages { ProgressView("Loading Conversation…") }
                    if store.messages.isEmpty, !store.isLoadingMessages {
                        ContentUnavailableView("Start a Conversation", systemImage: "bubble.left.and.bubble.right", description: Text("Send a message or add an attachment."))
                    }
                    ForEach(store.messages) { message in
                        MessageRow(message: message) {
                            Task { await store.retryMessage(message.id) }
                        }
                        .id(message.id)
                    }
                    if let interaction = store.pendingInteraction {
                        InteractionPanel(interaction: interaction, store: store)
                            .id(interaction.id)
                    }
                    Color.clear.frame(height: 1).id("transcript-end")
                }
                .frame(maxWidth: 760)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 100
            } action: { _, nearEnd in
                if isUserScrolling || nearEnd { followsEnd = nearEnd }
                if nearEnd { hasNewContent = false }
            }
            .onChange(of: store.messages.last?.text) { _, _ in contentChanged(proxy) }
            .onChange(of: store.messages.count) { _, _ in contentChanged(proxy) }
            .onChange(of: store.pendingInteraction?.id) { _, _ in contentChanged(proxy) }
            .onChange(of: store.selectedThreadID) { _, _ in
                followsEnd = true
                hasNewContent = false
                proxy.scrollTo("transcript-end", anchor: .bottom)
            }
            .safeAreaInset(edge: .bottom) {
                if hasNewContent && !followsEnd {
                    Button("New Messages", systemImage: "arrow.down") {
                        followsEnd = true
                        hasNewContent = false
                        proxy.scrollTo("transcript-end", anchor: .bottom)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .padding(8)
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            ComposerView(store: store) { showsCommands = true }
        }
        .navigationTitle(thread?.title.isEmpty == false ? thread?.title ?? "Conversation" : "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Session Options", systemImage: "slider.horizontal.3") { showsSession = true }
            }
            ToolbarOverflowMenu {
                Button("Commands", systemImage: "slash.circle") { showsCommands = true }
                if store.supportsThreadRename {
                    Button("Rename Thread", systemImage: "pencil") {
                        newTitle = thread?.title ?? ""
                        showsRename = true
                    }
                }
                if store.supportsThreadArchive {
                    Button("Archive Thread", systemImage: "archivebox") { showsArchiveConfirmation = true }
                }
            }
        }
        .sheet(isPresented: $showsCommands) { NavigationStack { CommandsView(store: store) } }
        .sheet(isPresented: $showsSession) { NavigationStack { SessionOptionsView(store: store) } }
        .alert("Rename Thread", isPresented: $showsRename) {
            TextField("Thread Title", text: $newTitle)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                guard let id = store.selectedThreadID, !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task { await store.renameThread(id, title: newTitle) }
            }
        }
        .confirmationDialog("Archive This Thread?", isPresented: $showsArchiveConfirmation, titleVisibility: .visible) {
            Button("Archive Thread") {
                guard let id = store.selectedThreadID else { return }
                Task { await store.archiveThread(id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This thread will be removed from the active thread list. Its conversation stays on your Hermes server.")
        }
    }

    private func contentChanged(_ proxy: ScrollViewProxy) {
        if followsEnd { proxy.scrollTo("transcript-end", anchor: .bottom) }
        else { hasNewContent = true }
    }
}
