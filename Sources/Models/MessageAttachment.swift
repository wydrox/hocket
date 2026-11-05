import CryptoKit
import Foundation

struct MessageAttachment: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case embeddedImage, serverFile, externalLink, unavailable }
    let id: String
    let kind: Kind
    let name: String
    let location: String
    let mimeType: String?
    let isImage: Bool
    let unavailableReason: String?

    static let maximumEmbeddedBytes = 8 * 1024 * 1024

    static func reference(_ raw: String, name: String? = nil, mimeType: String? = nil, image: Bool = false) -> Self {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("data:") {
            guard let separator = value.firstIndex(of: ",") else { return unavailable("Image data is invalid.") }
            let header = String(value[..<separator]).lowercased()
            let supported = ["image/png", "image/jpeg", "image/gif", "image/webp", "image/heic", "image/heif", "image/tiff", "image/bmp"]
            guard let mime = supported.first(where: { header == "data:\($0);base64" }),
                  value.utf8.count <= maximumEmbeddedBytes * 4 / 3 + 128,
                  let data = Data(base64Encoded: String(value[value.index(after: separator)...])), !data.isEmpty,
                  data.count <= maximumEmbeddedBytes else { return unavailable("This embedded image exceeds the 8 MiB preview limit or uses an unsupported format.") }
            return make(kind: .embeddedImage, name: name ?? "Embedded image", location: value, mime: mime, image: true)
        }
        if let url = safeExternalURL(value) {
            let filename = name ?? (url.lastPathComponent.isEmpty ? "External attachment" : url.lastPathComponent)
            return make(kind: .externalLink, name: filename, location: url.absoluteString, mime: mimeType, image: image || isImageName(filename))
        }
        if let path = safeServerPath(value) {
            let filename = name ?? path.split(separator: "/").last.map(String.init) ?? "Attachment"
            return make(kind: .serverFile, name: filename, location: path, mime: mimeType, image: image || isImageName(filename))
        }
        return unavailable("This attachment reference cannot be opened safely.", name: name)
    }

    static func staged(_ attachment: ChatAttachment) -> Self {
        reference(attachment.remotePath, name: attachment.name, mimeType: attachment.mimeType, image: attachment.isImage)
    }

    static func unavailable(_ reason: String, name: String? = nil) -> Self {
        let id = Data(SHA256.hash(data: Data("\(name ?? "Attachment"):\(reason)".utf8))).base64EncodedString()
        return Self(id: id, kind: .unavailable, name: name ?? "Attachment unavailable", location: "", mimeType: nil, isImage: false, unavailableReason: reason)
    }

    var embeddedData: Data? {
        guard kind == .embeddedImage, let comma = location.firstIndex(of: ","), location.utf8.count <= Self.maximumEmbeddedBytes * 4 / 3 + 128 else { return nil }
        return Data(base64Encoded: String(location[location.index(after: comma)...]))
    }

    var externalURL: URL? { kind == .externalLink ? Self.safeExternalURL(location) : nil }

    func serverPath(origin: URL) -> String? {
        if kind == .serverFile { return Self.safeServerPath(location) }
        guard kind == .externalLink, let url = externalURL, Self.sameOrigin(url, origin),
              url.path == "/api/fs/download", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let paths = components.queryItems?.filter { $0.name == "path" } ?? []
        guard paths.count == 1, let path = paths.first?.value else { return nil }
        return Self.safeServerPath(path)
    }

    static func safeExternalURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return components.url
    }

    static func safeServerPath(_ value: String) -> String? {
        let decoded = value.removingPercentEncoding ?? value
        guard !value.isEmpty, !decoded.hasPrefix("//"), !decoded.contains(":"), !value.contains("\\"),
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !decoded.split(separator: "/").contains(".."), !decoded.contains("\\") else { return nil }
        if value.hasPrefix("/api/fs/download?") {
            guard let parts = URLComponents(string: value), let items = parts.queryItems?.filter({ $0.name == "path" }), items.count == 1,
                  let path = items.first?.value,
                  !path.hasPrefix("/api/fs/download?") else { return nil }
            return safeServerPath(path)
        }
        guard !value.contains("?"), !value.contains("#") else { return nil }
        return value
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased() && lhs.host()?.lowercased() == rhs.host()?.lowercased() && (lhs.port ?? 443) == (rhs.port ?? 443)
    }

    static func isImageName(_ name: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp"].contains((name as NSString).pathExtension.lowercased())
    }

    private static func make(kind: Kind, name: String, location: String, mime: String?, image: Bool) -> Self {
        let id = Data(SHA256.hash(data: Data("\(kind.rawValue):\(location)".utf8))).base64EncodedString()
        return Self(id: id, kind: kind, name: name, location: location, mimeType: mime, isImage: image, unavailableReason: nil)
    }
}
