import Foundation

/// Mirrors session_history.py image blocks and desktop embedded-images/reference/MEDIA parsing.
struct AttachmentProjection {
    var text: String
    var attachments: [MessageAttachment]

    static func message(_ row: JSONValue) -> Self {
        let content = row["content"]
        let parts = content.array ?? (content.object != nil ? [content] : [])
        var textParts: [String] = []
        var attachments: [MessageAttachment] = []
        for part in parts {
            if let text = part.string { textParts.append(text); continue }
            switch part["type"].string {
            case "text", "input_text", "output_text": textParts.append(part["text"].string ?? part["content"].string ?? "")
            case "image_url", "input_image", "image":
                if let source = part["image_url"]["url"].string ?? part["image_url"].string {
                    attachments.append(.reference(source, image: true))
                } else { attachments.append(.unavailable("Hermes did not include an image reference.")) }
            case "file", "input_file":
                // The canonical history currently transports documents via @file references.
                // Preserve an explicit unavailable card for unknown provider file blocks.
                attachments.append(.unavailable("This file block has no supported Hermes download reference."))
            default:
                if let text = part["text"].string { textParts.append(text) }
            }
        }
        let text = parts.isEmpty ? (content.string ?? row["text"].string ?? "") : textParts.joined(separator: "\n")
        var projection = extract(text)
        for attachment in attachments where !projection.attachments.contains(where: { $0.id == attachment.id }) {
            if projection.attachments.count < 32 { projection.attachments.append(attachment) }
        }
        return projection
    }

    static func extract(_ source: String) -> Self {
        var text = source
        var attachments: [MessageAttachment] = []
        func collect(_ attachment: MessageAttachment) -> Bool {
            if attachments.contains(where: { $0.id == attachment.id }) { return true }
            guard attachments.count < 32 else { return false }
            attachments.append(attachment)
            return true
        }
        func replace(_ pattern: String, transform: (NSTextCheckingResult, String) -> String?) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let original = text
            let codeRanges = protectedCodeRanges(in: original)
            let matches = regex.matches(in: original, range: NSRange(original.startIndex..., in: original))
            for match in matches.reversed() {
                guard !codeRanges.contains(where: { NSLocationInRange(match.range.location, $0) }) else { continue }
                guard let range = Range(match.range, in: text), let replacement = transform(match, original) else { continue }
                text.replaceSubrange(range, with: replacement)
            }
        }
        // Quoted directive values match the authoritative context reference grammar.
        replace(#"@(image|file):(`[^`\n]+`|"[^"\n]+"|'[^'\n]+'|[^\s]+)"#) { match, original in
            guard let kindRange = Range(match.range(at: 1), in: original), let valueRange = Range(match.range(at: 2), in: original) else { return nil }
            guard collect(.reference(unquote(String(original[valueRange])), image: original[kindRange] == "image")) else { return nil }
            return ""
        }
        let extensions = "png|jpg|jpeg|gif|webp|bmp|tiff|svg|mp4|mov|avi|mkv|webm|3gp|mp3|m2a|wav|ogg|opus|m4a|flac|pdf|docx|doc|odt|rtf|txt|md|epub|xlsx|xls|ods|csv|tsv|json|xml|yaml|yml|kmz|kml|geojson|gpx|pptx|ppt|odp|key|zip|tar|gz|tgz|bz2|xz|7z|rar|apk|ipa|html|htm"
        let anchored = #"(?:~/|/)[^\n]+?\.(?:"# + extensions + #")(?=[\s`"'*_,;:)\]}]|\.|$)"#
        replace(#"MEDIA:\s*(`[^`\n]+`|"[^"\n]+"|'[^'\n]+'|"# + anchored + #"|[^\s`"]+)"#) { match, original in
            guard let range = Range(match.range(at: 1), in: original) else { return nil }
            let raw = String(original[range])
            let quoted = raw.first == "`" || raw.first == "\"" || raw.first == "'"
            let path = quoted ? unquote(raw) : raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            guard path.contains("/") || path.contains(".") else { return nil }
            guard collect(.reference(path)) else { return nil }
            return ""
        }
        // File/image Markdown links remain explicit taps; HTTPS links never auto-download.
        replace(#"(!?)\[([^\]\n]*)\]\(([^)\n]+)\)"#) { match, original in
            guard let imageRange = Range(match.range(at: 1), in: original), let labelRange = Range(match.range(at: 2), in: original),
                  let targetRange = Range(match.range(at: 3), in: original) else { return nil }
            let image = !original[imageRange].isEmpty
            let rawTarget = unquote(String(original[targetRange]))
            guard !rawTarget.hasPrefix("#") else { return nil }
            let components = URLComponents(string: rawTarget)
            let target = components?.scheme == nil && components?.host == nil && components?.query == nil ? (components?.path ?? rawTarget) : rawTarget
            let label = String(original[labelRange])
            let attachment = MessageAttachment.reference(target, name: label.isEmpty ? nil : label, image: image)
            let isFileLink = target.hasPrefix("/") || target.hasPrefix("./") || target.hasPrefix("~/") || (URL(string: target)?.pathExtension.isEmpty == false)
            guard image || isFileLink || attachment.kind == .unavailable else { return nil }
            guard collect(attachment) else { return nil }
            return ""
        }
        // Flattened canonical transcripts also carry bare data:image URLs.
        replace(#"data:image/[A-Za-z0-9.+_-]+;base64,[A-Za-z0-9+/=]+"#) { match, original in
            guard let range = Range(match.range, in: original) else { return nil }
            guard collect(.reference(String(original[range]), image: true)) else { return nil }
            return ""
        }
        if attachments.contains(where: \.isImage) {
            text = text.split(separator: "\n", omittingEmptySubsequences: false).filter { $0 != "[screenshot]" }.joined(separator: "\n")
        }
        return Self(text: text.trimmingCharacters(in: .whitespacesAndNewlines), attachments: Array(attachments.reversed()))
    }

    /// Attachment examples in Markdown code must remain byte-for-byte text.
    /// Check the match start so @file:`quoted path` outside code still works.
    private static func protectedCodeRanges(in text: String) -> [NSRange] {
        let patterns = [
            #"(?ms)^[ \t]{0,3}(`{3,}|~{3,})[^\n]*(?:\n|$).*?(?:^[ \t]{0,3}\1[ \t]*(?:\n|$)|\z)"#,
            #"`+[^`]*`+"#
        ]
        return patterns.flatMap { pattern -> [NSRange] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
        }
    }

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, trimmed.count > 1, ["`", "\"", "'", "<"].contains(String(first)),
              trimmed.last == (first == "<" ? ">" : first) else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }
}
