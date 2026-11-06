import SwiftUI

struct ConversationView: View {
    @Bindable var store: HermesStore
    var showsConnectionStatus = true
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
                    if showsConnectionStatus {
                        ConnectionStatusView(connection: store.connection, isStreaming: store.isStreaming)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = store.lastError {
                        DisclosureGroup {
                            Text(error).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                if store.connection != .connected {
                                    Button("Reconnect", systemImage: "arrow.clockwise") { Task { await store.restoreConnection() } }
                                }
                                Button("Dismiss") { store.lastError = nil }
                            }
                            .frame(minHeight: 44)
                        } label: {
                            Label("Conversation Needs Attention", systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    if store.connection != .connected, store.isStreaming {
                        Label("Connection interrupted. Reconnect to check the response before sending again.", systemImage: "wifi.slash")
                            .font(.subheadline)
                    }
                    if store.isReadOnlyConversation {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Saved conversation", systemImage: "archivebox")
                                .font(.headline)
                            Text("This conversation is available to read. Replies are not available through this connection.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if store.isLoadingMessages { ProgressView("Loading Conversation…") }
                    if store.messages.isEmpty, !store.isLoadingMessages {
                        if store.isReadOnlyConversation {
                            ContentUnavailableView("No Saved Messages", systemImage: "bubble.left.and.bubble.right")
                        } else {
                            ContentUnavailableView("Start a Conversation", systemImage: "bubble.left.and.bubble.right", description: Text("Send a message or add an attachment."))
                        }
                    }
                    if store.hasOlderMessages || store.isLoadingOlderMessages || store.olderMessagesError != nil {
                        earlierMessages
                    }
                    ForEach(store.messages) { message in
                        let downloadSessionID = store.selectedThreadID
                        let downloadAccountID = store.accountID
                        MessageRow(message: message, retry: { Task { await store.retryMessage(message.id) } },
                            canDownload: { store.canDownload($0) }, download: { attachment in
                                guard let id = downloadSessionID, store.accountID == downloadAccountID else { return nil }
                                return await store.downloadAttachment(attachment, sessionID: id)
                            })
                        .id("\(store.accountID):\(store.profileID):\(store.selectedThreadID ?? ""):\(message.id)")
                    }
                    if let interaction = store.pendingInteraction, !store.isReadOnlyConversation {
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
            .onChange(of: store.messages.last?.id) { _, _ in contentChanged(proxy) }
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
            if !store.isReadOnlyConversation {
                ComposerView(store: store) { showsCommands = true }
            }
        }
        .navigationTitle(threadTitle)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.openURL, OpenURLAction { url in
            MessageAttachment.safeExternalURL(url.absoluteString) == nil ? .discarded : .systemAction
        })
        .toolbar {
            if !store.isReadOnlyConversation {
                ToolbarItem(placement: .primaryAction) {
                    Button("Session Options", systemImage: "slider.horizontal.3") { showsSession = true }
                }
                ToolbarOverflowMenu {
                    Button("Commands", systemImage: "slash.circle") { showsCommands = true }
                    if store.supportsThreadRename {
                        Button("Rename Thread", systemImage: "pencil") {
                            newTitle = threadTitle == "New Thread" ? "" : threadTitle
                            showsRename = true
                        }
                    }
                    if store.supportsThreadArchive {
                        Button("Archive Thread", systemImage: "archivebox") { showsArchiveConfirmation = true }
                    }
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

    private var earlierMessages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isLoadingOlderMessages {
                ProgressView("Loading Earlier Messages…")
                    .frame(minHeight: 44)
            } else if store.olderMessagesError == nil {
                Button {
                    Task { await store.loadOlderMessages() }
                } label: {
                    Label("Load Earlier Messages", systemImage: "arrow.up")
                        .frame(minHeight: 44)
                }
            }
            if let error = store.olderMessagesError {
                Label("Couldn’t Load Earlier Messages", systemImage: "exclamationmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await store.loadOlderMessages() }
                } label: {
                    Label("Retry Loading Earlier Messages", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
                .disabled(store.isLoadingOlderMessages)
            }
        }
    }

    private var threadTitle: String {
        let title = (store.selectedThreadTitle ?? thread?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title == "Untitled conversation" ? "New Thread" : title
    }

    private func contentChanged(_ proxy: ScrollViewProxy) {
        if followsEnd { proxy.scrollTo("transcript-end", anchor: .bottom) }
        else { hasNewContent = true }
    }
}
