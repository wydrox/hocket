import ImageIO
import QuickLook
import SwiftUI

struct MessageAttachmentView: View {
    let attachment: MessageAttachment
    let canDownload: Bool
    let download: () async -> URL?
    @State private var thumbnail: UIImage?
    @State private var downloadedURL: URL?
    @State private var previewURL: URL?
    @State private var isDownloading = false
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 260)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityLabel(attachment.name)
            }
            Label(attachment.name, systemImage: attachment.isImage ? "photo" : "doc")
                .font(.subheadline)
                .lineLimit(3)
            if let reason = attachment.unavailableReason {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            } else if let downloadedURL {
                HStack(spacing: 16) {
                    Button("Preview", systemImage: "eye") { previewURL = downloadedURL }
                    ShareLink(item: downloadedURL) { Label("Share File", systemImage: "square.and.arrow.up") }
                }
                .frame(minHeight: 44)
            } else if canDownload {
                Button {
                    guard !isDownloading else { return }
                    isDownloading = true
                    downloadTask = Task {
                        defer { isDownloading = false }
                        guard let url = await download() else { return }
                        guard !Task.isCancelled else { AttachmentDownloader.removeCachedFile(url); return }
                        downloadedURL = url
                        previewURL = url
                        if attachment.isImage { thumbnail = Self.thumbnail(url: url) }
                    }
                } label: {
                    HStack {
                        if isDownloading { ProgressView().controlSize(.small) }
                        Label(isDownloading ? "Downloading…" : "Download and Preview", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(isDownloading)
                .frame(minHeight: 44)
                Text("Up to 32 MiB · Saved privately on this device")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let url = attachment.externalURL {
                Link(destination: url) { Label("Open External Link", systemImage: "arrow.up.right.square") }
                    .frame(minHeight: 44)
                Text(url.host() ?? "External website").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .quickLookPreview($previewURL)
        .task(id: attachment.id) {
            if let data = attachment.embeddedData { thumbnail = Self.thumbnail(data: data) }
        }
        .onDisappear {
            downloadTask?.cancel()
            if previewURL == nil, let downloadedURL {
                AttachmentDownloader.removeCachedFile(downloadedURL)
                self.downloadedURL = nil
            }
        }
    }

    private static func thumbnail(data: Data) -> UIImage? {
        guard data.count <= MessageAttachment.maximumEmbeddedBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(source: source)
    }

    private static func thumbnail(url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(source: source)
    }

    private static func thumbnail(source: CGImageSource) -> UIImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0, width.doubleValue * height.doubleValue <= 80_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1_024,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
