import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    let retry: () -> Void

    @ContentBuilder
    var body: some View {
        if message.role == .tool {
            DisclosureGroup {
                MarkdownMessageView(text: message.text)
            } label: {
                Label(message.toolName ?? "Tool Activity", systemImage: "wrench.and.screwdriver")
                    .font(.subheadline)
            }
            .padding(12)
            .background(.quaternary, in: .rect(cornerRadius: 12))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(roleTitle).font(.subheadline.bold()).foregroundStyle(.secondary)
                    if message.status == .pending { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }
                if !message.text.isEmpty { MarkdownMessageView(text: message.text) }
                if !message.reasoning.isEmpty {
                    DisclosureGroup("Reasoning") {
                        MarkdownMessageView(text: message.reasoning)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                if message.status == .failed {
                    Label(message.role == .user ? "Delivery Unconfirmed" : "Response Incomplete", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                    if message.role == .user {
                        Button("Check and Retry", systemImage: "arrow.clockwise", action: retry)
                            .frame(minHeight: 44)
                    }
                } else if message.status == .pending {
                    Text("Pending").font(.subheadline).foregroundStyle(.secondary)
                } else if message.role == .user, message.status == .complete {
                    Text("Sent").font(.subheadline).foregroundStyle(.secondary)
                }
                if !message.text.isEmpty, message.status != .pending {
                    HStack(spacing: 12) {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
                            .frame(minWidth: 44, minHeight: 44)
                        ShareLink(item: message.text) { Label("Share", systemImage: "square.and.arrow.up") }
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                }
            }
            .padding(message.role == .user ? 12 : 0)
            .background {
                if message.role == .user { RoundedRectangle(cornerRadius: 16).fill(.quaternary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    private var roleTitle: String {
        switch message.role {
        case .user: "You"
        case .assistant: "Hermes · AI"
        case .system: "Session"
        case .tool: message.toolName ?? "Tool"
        }
    }
}
