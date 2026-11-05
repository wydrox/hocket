import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @Bindable var store: HermesStore
    let openCommands: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var photo: PhotosPickerItem?
    @State private var showsFiles = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var isSending = false
    @State private var isStopping = false
    @State private var commandToReview: GatewayCommand?

    private let maximumAttachmentBytes = 16 * 1024 * 1024

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(store.attachments) { attachment in
                            HStack(spacing: 8) {
                                Image(systemName: attachment.isImage ? "photo" : "doc")
                                VStack(alignment: .leading) {
                                    Text(attachment.name).lineLimit(1)
                                    Text(Int64(attachment.byteCount), format: .byteCount(style: .file))
                                        .foregroundStyle(.secondary)
                                }
                                Button("Remove \(attachment.name)", systemImage: "xmark.circle.fill") {
                                    store.removeAttachment(attachment.id)
                                }
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                            }
                            .font(.subheadline)
                            .padding(.leading, 12)
                            .background(.quaternary, in: .capsule)
                        }
                    }
                }
                Text("Uploaded to Hermes. Included when you send this message.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isImporting { ProgressView("Preparing Attachment…").font(.subheadline) }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    if store.supportsAttachments {
                        Section("Upload to \(URL(string: store.endpoint)?.host ?? "Hermes")") {
                            PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .compatible) {
                                Label("Upload Photo", systemImage: "photo")
                            }
                            Button("Upload File", systemImage: "doc") { showsFiles = true }
                        }
                    }
                    Button("Commands", systemImage: "slash.circle", action: openCommands)
                } label: {
                    Label("Add Attachment or Command", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(store.isLoadingMessages || isImporting || store.isUploadingAttachment)
                TextField("Message Hermes", text: $store.composerText, axis: .vertical)
                    .lineLimit(1...(dynamicTypeSize.isAccessibilitySize ? 3 : 7))
                    .padding(.vertical, 12)
                    .accessibilityLabel("Message Hermes")
                    .disabled(store.isLoadingMessages)
                if store.isStreaming && store.supportsInterrupt {
                    Button(isStopping ? "Stop Requested" : "Stop Response", systemImage: "stop.fill") {
                        guard !isStopping else { return }
                        isStopping = true
                        Task { await store.interrupt(); isStopping = false }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(store.connection != .connected || isStopping)
                } else {
                    Button("Send Message", systemImage: "arrow.up") { send() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            if store.composerText.hasPrefix("/"), !store.commands.isEmpty {
                Button("Browse Matching Commands", systemImage: "slash.circle", action: openCommands)
                    .font(.subheadline)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): importFile(url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
        .sheet(item: $commandToReview) { command in
            NavigationStack {
                CommandDetailView(store: store, command: command) { commandToReview = nil }
            }
        }
    }

    private var canSend: Bool {
        store.connection == .connected && !store.isLoadingMessages && !isImporting && !isSending && !store.isSending && !store.isStreaming &&
        (!store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.attachments.isEmpty)
    }

    private func send() {
        guard canSend else { return }
        let original = store.composerText
        if original.hasPrefix("/") {
            let firstSpace = original.firstIndex(where: \.isWhitespace) ?? original.endIndex
            let name = String(original[..<firstSpace].dropFirst())
            if let command = store.commands.first(where: { $0.name.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == name }) {
                guard store.attachments.isEmpty else {
                    importError = "Remove attachments before running a command."
                    return
                }
                commandToReview = command
                return
            }
        }
        isSending = true
        Task { await store.sendMessage(); isSending = false }
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        let threadID = store.selectedThreadID
        isImporting = true
        importError = nil
        Task {
            defer { isImporting = false; photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    importError = "This photo couldn’t be read. Choose another photo."
                    return
                }
                guard data.count <= maximumAttachmentBytes else { importError = "Choose an attachment smaller than 16 MB."; return }
                guard store.selectedThreadID == threadID else {
                    importError = "The conversation changed. Choose the attachment again for this thread."
                    return
                }
                let type = imageType(data) ?? item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
                await store.addAttachment(data: data, name: "Photo.\(type?.preferredFilenameExtension ?? "jpg")", mimeType: type?.preferredMIMEType ?? "image/jpeg")
            } catch { importError = error.localizedDescription }
        }
    }

    private func importFile(_ url: URL) {
        let threadID = store.selectedThreadID
        isImporting = true
        importError = nil
        Task {
            defer { isImporting = false }
            do {
                let limit = maximumAttachmentBytes
                let data = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard let size = values.fileSize, size <= limit else {
                        throw CocoaError(.fileReadTooLarge)
                    }
                    return try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                guard store.selectedThreadID == threadID else {
                    importError = "The conversation changed. Choose the attachment again for this thread."
                    return
                }
                let type = UTType(filenameExtension: url.pathExtension)
                await store.addAttachment(data: data, name: url.lastPathComponent, mimeType: type?.preferredMIMEType ?? "application/octet-stream")
            } catch {
                importError = "This file couldn’t be read. Choose an accessible file smaller than 16 MB."
            }
        }
    }

    private func imageType(_ data: Data) -> UTType? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if data.starts(with: Array("GIF8".utf8)) { return .gif }
        if data.count >= 12, data.prefix(4) == Data("RIFF".utf8), data.dropFirst(8).prefix(4) == Data("WEBP".utf8) { return .webP }
        return nil
    }
}
