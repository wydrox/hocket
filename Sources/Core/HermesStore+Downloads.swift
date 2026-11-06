import Foundation

extension HermesStore {
    func canDownload(_ attachment: MessageAttachment) -> Bool {
        if attachment.kind == .embeddedImage { return true }
        guard !isReadOnlyConversation else { return false }
        guard let credentials, let endpoint = try? GatewayEndpoint(credentials.endpoint) else { return false }
        return attachment.serverPath(origin: endpoint.origin) != nil
    }

    func downloadAttachment(_ attachment: MessageAttachment, sessionID: String) async -> URL? {
        lastError = nil
        do {
            guard let saved = credentials, !accountID.isEmpty, !profileID.isEmpty, sessionID == selectedThreadID else { throw GatewayError.missingSession }
            let capturedAccount = accountID
            let capturedProfile = profileID
            let origin = try GatewayEndpoint(saved.endpoint).origin
            let downloader = AttachmentDownloader()
            let url: URL
            if attachment.kind == .embeddedImage, let data = attachment.embeddedData {
                url = try await downloader.save(data, name: attachment.name, mimeType: attachment.mimeType)
            } else {
                guard !isReadOnlyConversation else {
                    throw GatewayError.invalidResponse("File downloads are not available for this saved conversation through this connection.")
                }
                guard let path = attachment.serverPath(origin: origin) else {
                    throw GatewayError.invalidResponse("External attachments open as HTTPS links. Hermes credentials are never sent to another origin.")
                }
                let info = try await transport.call("session.info", params: ["session_id": .string(sessionID)])
                guard accountID == capturedAccount, profileID == capturedProfile, credentials?.endpoint == saved.endpoint,
                      selectedThreadID == sessionID else { throw CancellationError() }
                let target = try Self.attachmentDownloadURL(origin: origin, path: path, sessionID: sessionID, profile: info["profile_name"].string)
                var request = URLRequest(url: target)
                request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/octet-stream,*/*;q=0.8", forHTTPHeaderField: "Accept")
                url = try await downloader.download(request, name: attachment.name)
            }
            guard !Task.isCancelled, accountID == capturedAccount, profileID == capturedProfile,
                  credentials?.endpoint == saved.endpoint, selectedThreadID == sessionID else {
                AttachmentDownloader.removeCachedFile(url)
                throw CancellationError()
            }
            return url
        } catch { report(error); return nil }
    }

    nonisolated static func attachmentDownloadURL(origin: URL, path: String, sessionID: String, profile: String?) throws -> URL {
        let endpoint = try GatewayEndpoint(origin.absoluteString)
        guard let safePath = MessageAttachment.safeServerPath(path), !sessionID.isEmpty,
              var parts = URLComponents(url: endpoint.httpURL(path: "api/fs/download"), resolvingAgainstBaseURL: false) else { throw GatewayError.invalidEndpoint }
        parts.queryItems = [URLQueryItem(name: "path", value: safePath), URLQueryItem(name: "session_id", value: sessionID)]
        if let profile, !profile.isEmpty { parts.queryItems?.append(URLQueryItem(name: "profile", value: profile)) }
        guard let url = parts.url, MessageAttachment.sameOrigin(url, origin) else { throw GatewayError.invalidEndpoint }
        return url
    }
}
