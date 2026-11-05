import SwiftUI

struct ThreadRow: View {
    let thread: HermesThread

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(thread.title.isEmpty ? "Untitled Thread" : thread.title)
                .font(.headline)
                .lineLimit(2)
            if !thread.preview.isEmpty {
                Text(thread.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if thread.isRunning {
                Label("Working", systemImage: "ellipsis.bubble")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let updated = thread.updatedAt {
                Text(updated, style: .relative)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
