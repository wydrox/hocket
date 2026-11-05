import Foundation
import UniformTypeIdentifiers

actor AttachmentDownloader {
    static let maximumBytes = 32 * 1024 * 1024

    func download(_ request: URLRequest, name: String) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayError.invalidFrame }
        guard response.statusCode == 200 else {
            throw GatewayError.invalidResponse("Hermes could not download this attachment (HTTP \(response.statusCode)).")
        }
        guard response.expectedContentLength <= Self.maximumBytes else {
            throw GatewayError.invalidResponse("This attachment exceeds the 32 MiB download limit.")
        }
        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            guard data.count < Self.maximumBytes else { throw GatewayError.invalidResponse("This attachment exceeds the 32 MiB download limit.") }
            data.append(byte)
            if data.count.isMultiple(of: 65_536) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return try save(data, name: name, mimeType: response.mimeType)
    }

    func save(_ data: Data, name: String, mimeType: String?) throws -> URL {
        guard !data.isEmpty, data.count <= Self.maximumBytes else {
            throw GatewayError.invalidResponse("The attachment is empty or exceeds the 32 MiB download limit.")
        }
        let folder = URL.cachesDirectory.appending(path: "HermesPocketAttachments", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var filename = (name as NSString).lastPathComponent
        filename = String(filename.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" && $0 != "\\" }.map { String($0) }.joined().prefix(140))
        if filename.isEmpty || filename == "." || filename == ".." { filename = "Attachment" }
        if (filename as NSString).pathExtension.isEmpty, let mimeType, let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension { filename += "." + ext }
        var url = folder.appending(path: filename, directoryHint: .notDirectory)
        do {
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    nonisolated static func removeCachedFile(_ url: URL) {
        let root = URL.cachesDirectory.appending(path: "HermesPocketAttachments", directoryHint: .isDirectory).standardizedFileURL
        let folder = url.deletingLastPathComponent().standardizedFileURL
        guard folder.deletingLastPathComponent() == root, UUID(uuidString: folder.lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
