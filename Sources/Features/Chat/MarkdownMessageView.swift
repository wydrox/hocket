import SwiftUI
import UIKit

/// Markdown is rendered as selectable text. Fenced code stays readable without
/// executing content or passing the transcript to a web view.
struct MarkdownMessageView: View {
    let text: String

    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                if block.isCode {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(block.language.isEmpty ? "Code" : block.language)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy Code", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = block.content
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        ScrollView(.horizontal) {
                            Text(block.content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.bottom, 12)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(.quaternary, in: .rect(cornerRadius: 12))
                } else {
                    Text(markdown(block.content))
                        .font(block.headingLevel > 0 ? (block.headingLevel <= 2 ? .title3.bold() : .headline) : .body)
                        .foregroundStyle(block.isQuote ? .secondary : .primary)
                        .padding(.leading, block.isQuote ? 12 : 0)
                        .overlay(alignment: .leading) {
                            if block.isQuote { Rectangle().fill(.secondary).frame(width: 2) }
                        }
                        .accessibilityAddTraits(block.headingLevel > 0 ? .isHeader : [])
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
    }
}
