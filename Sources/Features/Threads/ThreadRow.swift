import SwiftUI

struct ThreadRow: View {
    let thread: HermesThread
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    title
                    activity
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    activity
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            if !thread.preview.isEmpty {
                Text(thread.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text(thread.title.isEmpty ? "Untitled Thread" : thread.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var activity: some View {
        Group {
            if thread.isRunning {
                Label("Working", systemImage: "ellipsis.bubble")
            } else if let updated = thread.updatedAt {
                Text(updated, style: .relative)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }
}
