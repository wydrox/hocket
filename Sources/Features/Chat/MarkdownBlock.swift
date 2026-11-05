import Foundation

struct MarkdownBlock: Identifiable {
    let id: Int
    let content: String
    let isCode: Bool
    let language: String
    var headingLevel: Int = 0
    var isQuote = false

    static func parse(_ source: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var lines: [String] = []
        var code = false
        var language = ""
        for line in source.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if !lines.isEmpty {
                    append(lines: lines, isCode: code, language: language, to: &result)
                    lines.removeAll(keepingCapacity: true)
                }
                code.toggle()
                language = code ? String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) : ""
            } else {
                lines.append(line)
            }
        }
        if !lines.isEmpty {
            append(lines: lines, isCode: code, language: language, to: &result)
        }
        return result
    }

    private static func append(lines: [String], isCode: Bool, language: String, to result: inout [MarkdownBlock]) {
        if isCode {
            result.append(.init(id: result.count, content: lines.joined(separator: "\n"), isCode: true, language: language))
            return
        }
        var paragraph: [String] = []
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.init(id: result.count, content: paragraph.joined(separator: "\n"), isCode: false, language: ""))
            paragraph.removeAll(keepingCapacity: true)
        }
        for line in lines {
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                flushParagraph()
                result.append(.init(id: result.count, content: String(line.dropFirst(hashes + 1)), isCode: false, language: "", headingLevel: hashes))
            } else if line.hasPrefix("> ") {
                flushParagraph()
                result.append(.init(id: result.count, content: String(line.dropFirst(2)), isCode: false, language: "", isQuote: true))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                paragraph.append("• " + String(line.dropFirst(2)))
            } else { paragraph.append(line) }
        }
        flushParagraph()
    }
}
