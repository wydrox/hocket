import Foundation
import Testing
@testable import HermesPocket

struct AttachmentProjectionTests {
    private let pixel = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6WQAAAABJRU5ErkJggg=="

    @Test func codeExamplesAndAnchorLinksRemainUnchanged() {
        let text = """
        ```swift
        let input = "@file:/tmp/example.pdf"
        let sample = "![plot](/tmp/chart.png)"
        ```
        Use `@image:/tmp/example.png` in your command.
        [Details](#details)
        """
        let projection = AttachmentProjection.extract(text)
        #expect(projection.text == text)
        #expect(projection.attachments.isEmpty)
    }

    @Test func referencesBeyondCardLimitRemainVisible() {
        let projection = AttachmentProjection.extract((1...35).map { "@file:/tmp/file-\($0).pdf" }.joined(separator: "\n"))
        #expect(projection.attachments.count == 32)
        let preserved = projection.text.components(separatedBy: "@file:").count - 1
        #expect(preserved == 3)
    }

    @Test func multimodalImageBlocksKeepCaptionAndReferences() throws {
        let row: JSONValue = .object(["role": .string("user"), "row_id": .integer(42), "content": .array([
            .object(["type": .string("text"), "text": .string("Compare these")]),
            .object(["type": .string("image_url"), "image_url": .object(["url": .string(pixel)])]),
            .object(["type": .string("input_image"), "image_url": .string("https://images.example/photo.png")])
        ])])
        let message = try #require(HermesStore.message(row, fallbackID: "fallback"))
        #expect(message.text == "Compare these")
        #expect(message.attachments.count == 2)
        #expect(message.attachments.contains(where: { $0.kind == .embeddedImage && $0.embeddedData != nil }))
        #expect(message.attachments.contains(where: { $0.kind == .externalLink }))
        #expect(!message.text.contains("base64"))
    }

    @Test func persistedQuotedReferencesAndSpacedMediaBecomeAttachmentCards() {
        let projection = AttachmentProjection.extract("""
        Review these files.
        @image:`/srv/cache/photo one.png`
        @file:"/srv/work/Quarterly Report.pdf"
        MEDIA:/srv/out/Result Chart.png
        [screenshot]
        """)
        #expect(projection.text == "Review these files.")
        #expect(projection.attachments.count == 3)
        #expect(projection.attachments.contains(where: { $0.location == "/srv/cache/photo one.png" && $0.isImage }))
        #expect(projection.attachments.contains(where: { $0.location == "/srv/work/Quarterly Report.pdf" && !$0.isImage }))
        #expect(projection.attachments.contains(where: { $0.location == "/srv/out/Result Chart.png" }))
    }

    @Test func embeddedMarkdownDoesNotLeaveRawBase64OrBrokenLink() {
        let projection = AttachmentProjection.extract("Here is ![Plot](\(pixel))")
        #expect(projection.text == "Here is")
        #expect(projection.attachments.count == 1)
        #expect(projection.attachments.first?.kind == .embeddedImage)
    }

    @Test func markdownServerPathDecodesFilenameWithoutOpeningPhoneFiles() {
        let projection = AttachmentProjection.extract("[Report](/srv/Quarterly%20Report.pdf)")
        #expect(projection.attachments.first?.location == "/srv/Quarterly Report.pdf")
        #expect(projection.attachments.first?.kind == .serverFile)
        let localPhoneLink = AttachmentProjection.extract("[Private](file:///private/data.pdf)")
        #expect(localPhoneLink.attachments.first?.kind == .unavailable)
    }

    @Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "http://files.example/a.pdf", "//files.example/a.pdf", "../private/file.pdf", "/srv/%2e%2e/private", "https://user:password@example.com/a.pdf", "/tmp/a%0Ab.pdf"])
    func unsafeReferencesCannotBecomeDownloadsOrExternalLinks(_ raw: String) {
        let attachment = MessageAttachment.reference(raw)
        #expect(attachment.kind == .unavailable)
        #expect(attachment.externalURL == nil)
    }

    @Test func externalOriginCannotBeUpgradedToAuthenticatedDownload() throws {
        let origin = try GatewayEndpoint("https://hermes.example:8443").origin
        let external = MessageAttachment.reference("https://other.example/api/fs/download?path=/private/report.pdf")
        #expect(external.serverPath(origin: origin) == nil)
        #expect(external.externalURL?.host() == "other.example")
        let sameHostWrongPort = MessageAttachment.reference("https://hermes.example/api/fs/download?path=/private/report.pdf")
        #expect(sameHostWrongPort.serverPath(origin: origin) == nil)
        let sameOrigin = MessageAttachment.reference("https://hermes.example:8443/api/fs/download?path=%2Fsrv%2Freport.pdf&session_id=forged&profile=forged")
        #expect(sameOrigin.serverPath(origin: origin) == "/srv/report.pdf")
        let rebuilt = try HermesStore.attachmentDownloadURL(origin: origin, path: "/srv/report.pdf", sessionID: "real-session", profile: "work")
        let parts = try #require(URLComponents(url: rebuilt, resolvingAgainstBaseURL: false))
        #expect(parts.host == "hermes.example")
        #expect(parts.port == 8443)
        #expect(parts.path == "/api/fs/download")
        #expect(parts.queryItems?.contains(URLQueryItem(name: "session_id", value: "real-session")) == true)
        #expect(parts.queryItems?.contains(URLQueryItem(name: "profile", value: "work")) == true)
        #expect(!rebuilt.absoluteString.contains("forged"))
        #expect(!rebuilt.absoluteString.contains("token"))
    }

    @Test func duplicateImageDirectivesAreDeduplicatedAndUnknownFilesStayVisible() {
        let projection = AttachmentProjection.extract("@image:/srv/a.png\n@image:/srv/a.png")
        #expect(projection.attachments.count == 1)
        let unknown = AttachmentProjection.message(.object(["content": .array([.object(["type": .string("input_file"), "file_id": .string("provider-only")])])]))
        #expect(unknown.attachments.first?.kind == .unavailable)
    }

    @Test func outgoingStagedFileKeepsGatewayPathAndName() {
        let staged = ChatAttachment(id: "upload", name: "Report.pdf", mimeType: "application/pdf", byteCount: 100, isImage: false, remotePath: "/staged/report.pdf", referenceText: "@file:/staged/report.pdf")
        let attachment = MessageAttachment.staged(staged)
        #expect(attachment.kind == .serverFile)
        #expect(attachment.name == "Report.pdf")
        #expect(attachment.location == "/staged/report.pdf")
    }
}
