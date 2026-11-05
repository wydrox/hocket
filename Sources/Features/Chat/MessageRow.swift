import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    let retry: () -> Void
    let canDownload: (MessageAttachment) -> Bool
    let download: (MessageAttachment) async -> URL?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    @ContentBuilder
    var body: some View {
        if message.role == .tool || message.role == .system {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if !message.text.isEmpty { MarkdownMessageView(text: message.text) }
                    attachmentCards
                }
                .padding(.top, 8)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if message.status == .pending || message.status == .streaming {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("Activity in progress")
                    } else {
                        Image(systemName: activitySymbol).accessibilityHidden(true)
                    }
                    Text(activityTitle)
                        .lineLimit(2)
                    if message.role == .tool {
                        Text(activityStatus).font(.caption)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(message.status == .failed ? Color.red : Color.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .contextMenu {
                messageActions
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                if message.role == .user { Spacer(minLength: oppositeInset) }
                ViewThatFits(in: .horizontal) {
                    bubble.fixedSize(horizontal: true, vertical: false)
                    bubble
                }
                .frame(maxWidth: bubbleWidth, alignment: message.role == .user ? .trailing : .leading)
                .contextMenu {
                    messageActions
                }
                .accessibilityElement(children: .contain)
                if message.role != .user { Spacer(minLength: oppositeInset) }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(message.role == .user ? "You" : "Hermes · AI")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if message.status == .pending { ProgressView().controlSize(.small) }
            }
            if !message.text.isEmpty { MarkdownMessageView(text: message.text) }
            attachmentCards
            if !message.reasoning.isEmpty {
                DisclosureGroup("Reasoning") {
                    MarkdownMessageView(text: message.reasoning)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            if message.status == .failed {
                Label(message.role == .user ? "Delivery Unconfirmed" : "Response Incomplete", systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                if message.role == .user {
                    Button("Check and Retry", systemImage: "arrow.clockwise", action: retry)
                        .frame(minHeight: 44)
                }
            } else if message.status == .pending {
                Text("Pending").font(.caption).foregroundStyle(.secondary)
            } else if message.role == .user, message.status == .complete {
                Text("Sent").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(message.role == .user ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.secondary.opacity(0.12), lineWidth: 1)
        }
    }

    @ContentBuilder
    private var messageActions: some View {
        if !message.text.isEmpty, message.status != .pending {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
            ShareLink(item: message.text) { Label("Share", systemImage: "square.and.arrow.up") }
        }
    }

    private var attachmentCards: some View {
        ForEach(message.attachments) { attachment in
            MessageAttachmentView(attachment: attachment, canDownload: canDownload(attachment)) { await download(attachment) }
        }
    }

    private var oppositeInset: CGFloat { dynamicTypeSize.isAccessibilitySize ? 12 : 28 }
    private var bubbleWidth: CGFloat? {
        availableWidth > 0 ? max(1, min(600, availableWidth - oppositeInset)) : nil
    }

    private var activityTitle: String {
        if message.role == .tool { return message.toolName ?? "Tool Activity" }
        return message.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Session Activity"
    }

    private var activitySymbol: String {
        if message.status == .failed { return "exclamationmark.circle" }
        return message.role == .tool ? "checkmark.circle" : "circle.fill"
    }

    private var activityStatus: String {
        switch message.status {
        case .pending, .streaming: "Running"
        case .failed: "Failed"
        case .complete: "Complete"
        }
    }
}
