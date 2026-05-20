import SwiftUI
import UniformTypeIdentifiers
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(PhotosUI) && os(iOS)
import PhotosUI
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct PendingAttachment: Identifiable, Hashable {
    let id = UUID()
    let filename: String
    let contentType: String
    let data: Data

    var formattedSize: String {
        ByteCountFormatter.financeFileSize.string(fromByteCount: Int64(data.count))
    }
}

struct AttachmentSection: View {
    @Bindable var environment: AppEnvironment
    let ownerType: String
    let ownerID: String
    @State private var isImportingFiles = false
    @State private var preview: AttachmentPreviewItem?
#if canImport(PhotosUI) && os(iOS)
    @State private var pickedPhotos: [PhotosPickerItem] = []
#endif

    private var attachments: [AttachmentDTO] {
        environment.attachmentViewModel.attachments(ownerType: ownerType, ownerID: ownerID)
    }

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("附件", systemImage: "paperclip")
                        .font(FinanceTypography.headline)
                    Spacer()
                    if environment.attachmentViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                uploadControls

                if attachments.isEmpty {
                    Text("暂无附件")
                        .font(FinanceTypography.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            AttachmentRow(
                                attachment: attachment,
                                preview: { Task { await preview(attachment) } },
                                delete: { Task { await delete(attachment) } }
                            )
                        }
                    }
                }

                if let message = environment.attachmentViewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
        }
        .task(id: "\(ownerType)-\(ownerID)") {
            try? await environment.attachmentViewModel.refresh(ownerType: ownerType, ownerID: ownerID)
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImport(result) }
        }
#if os(macOS)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleDrop(providers)
        }
#endif
#if canImport(PhotosUI) && os(iOS)
        .onChange(of: pickedPhotos) { _, items in
            Task { await uploadPhotos(items) }
        }
#endif
        .sheet(item: $preview) { item in
            AttachmentPreviewSheet(item: item)
        }
    }

    @ViewBuilder
    private var uploadControls: some View {
        ViewThatFits {
            HStack(spacing: 10) {
                uploadButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                uploadButtons
            }
        }
    }

    @ViewBuilder
    private var uploadButtons: some View {
#if canImport(PhotosUI) && os(iOS)
        PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 8, matching: .images) {
            Label("选择图片", systemImage: "photo")
        }
        .buttonStyle(.bordered)
#endif
        Button {
            isImportingFiles = true
        } label: {
            Label("上传文件", systemImage: "doc.badge.plus")
        }
        .buttonStyle(.borderedProminent)
    }

    @MainActor
    private func preview(_ attachment: AttachmentDTO) async {
        do {
            let data = try await environment.attachmentViewModel.download(attachment)
            preview = AttachmentPreviewItem(attachment: attachment, data: data)
        } catch {
            environment.attachmentViewModel.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ attachment: AttachmentDTO) async {
        do {
            try await environment.attachmentViewModel.delete(attachment)
        } catch {
            environment.attachmentViewModel.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        do {
            for url in try result.get() {
                let pending = try PendingAttachment.from(url: url)
                try await environment.attachmentViewModel.upload(
                    ownerType: ownerType,
                    ownerID: ownerID,
                    filename: pending.filename,
                    contentType: pending.contentType,
                    data: pending.data
                )
            }
        } catch {
            environment.attachmentViewModel.errorMessage = error.localizedDescription
        }
    }

#if canImport(PhotosUI) && os(iOS)
    @MainActor
    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        defer { pickedPhotos = [] }
        do {
            for (index, item) in items.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let filename = "photo-\(Int(Date().timeIntervalSince1970))-\(index + 1).jpg"
                try await environment.attachmentViewModel.upload(
                    ownerType: ownerType,
                    ownerID: ownerID,
                    filename: filename,
                    contentType: "image/jpeg",
                    data: data
                )
            }
        } catch {
            environment.attachmentViewModel.errorMessage = error.localizedDescription
        }
    }
#endif

#if os(macOS)
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                Task { @MainActor in
                    do {
                        let pending = try PendingAttachment.from(url: url)
                        try await environment.attachmentViewModel.upload(
                            ownerType: ownerType,
                            ownerID: ownerID,
                            filename: pending.filename,
                            contentType: pending.contentType,
                            data: pending.data
                        )
                    } catch {
                        environment.attachmentViewModel.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        return true
    }
#endif
}

private struct AttachmentRow: View {
    let attachment: AttachmentDTO
    let preview: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(FinanceTokens.Brand.primary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(FinanceTokens.Brand.primary.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(ByteCountFormatter.financeFileSize.string(fromByteCount: Int64(attachment.sizeBytes))) · \(attachment.contentType)")
                    .font(.caption2)
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            Spacer(minLength: 8)
            Button(action: preview) {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("预览附件")
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除附件")
        }
        .padding(10)
        .background(FinanceTokens.Surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.sm))
    }

    private var iconName: String {
        if attachment.contentType.contains("pdf") {
            return "doc.richtext"
        }
        if attachment.contentType.hasPrefix("image/") {
            return "photo"
        }
        return "doc"
    }
}

private struct AttachmentPreviewItem: Identifiable {
    let id = UUID()
    let attachment: AttachmentDTO
    let data: Data
}

private struct AttachmentPreviewSheet: View {
    let item: AttachmentPreviewItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if item.attachment.contentType.hasPrefix("image/") {
                    AttachmentImagePreview(data: item.data)
                } else if item.attachment.contentType.contains("pdf") {
                    PDFKitPreview(data: item.data)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc")
                            .font(.largeTitle)
                            .foregroundStyle(FinanceTokens.Text.secondary)
                        Text(item.attachment.filename)
                            .font(.headline)
                        Text(ByteCountFormatter.financeFileSize.string(fromByteCount: Int64(item.data.count)))
                            .font(.caption)
                            .foregroundStyle(FinanceTokens.Text.secondary)
                    }
                }
            }
            .frame(minWidth: 360, minHeight: 420)
            .navigationTitle(item.attachment.filename)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct AttachmentImagePreview: View {
    let data: Data

    var body: some View {
#if os(iOS)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding()
        } else {
            Text("无法预览图片")
        }
#elseif os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding()
        } else {
            Text("无法预览图片")
        }
#else
        Text("无法预览图片")
#endif
    }
}

#if canImport(PDFKit)
#if os(iOS)
private struct PDFKitPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(data: data)
    }
}
#elseif os(macOS)
private struct PDFKitPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(data: data)
    }
}
#endif
#else
private struct PDFKitPreview: View {
    let data: Data

    var body: some View {
        Text("当前平台无法预览 PDF")
    }
}
#endif

extension PendingAttachment {
    static func from(url: URL) throws -> PendingAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension)
        return PendingAttachment(
            filename: url.lastPathComponent,
            contentType: type?.preferredMIMEType ?? "application/octet-stream",
            data: data
        )
    }
}

private extension ByteCountFormatter {
    static let financeFileSize: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}
