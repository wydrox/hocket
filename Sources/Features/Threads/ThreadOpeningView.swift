import SwiftUI

struct ThreadOpeningView: View {
    @Bindable var store: HermesStore
    let threadID: String

    var body: some View {
        Group {
            if store.isLoadingMessages {
                ProgressView("Loading Conversation…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Couldn’t Open Conversation", systemImage: "exclamationmark.bubble")
                } description: {
                    Text(store.threadOpenError ?? "This conversation couldn’t be loaded. Try again.")
                } actions: {
                    Button {
                        Task { await store.openThread(threadID) }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(threadTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var threadTitle: String {
        let title = (store.threads.first { $0.id == threadID }?.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title == "Untitled conversation" ? "Conversation" : title
    }
}
