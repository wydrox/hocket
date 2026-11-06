import SwiftUI

struct SidebarConnectionFooter: View {
    let store: HermesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ConnectionStatusView(connection: store.connection)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(conversationCount)\(store.hasOlderThreads ? " · More available" : "")")
                if let updated = store.lastThreadsUpdatedAt {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("Updated \(updated, format: .relative(presentation: .named))")
                    }
                } else {
                    Text("Not updated yet")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("threads.connectionFooter")
    }

    private var conversationCount: String {
        store.loadedConversationCount == 1
            ? String(localized: "1 conversation loaded")
            : String(localized: "\(store.loadedConversationCount) conversations loaded")
    }
}
