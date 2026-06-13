import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)

// ReimbursementAttachmentsSheet — D6 凭证 management for a single claim.
//
// owner_type = "reimbursement_claim", owner_id = claim.id.
//   listAttachments / uploadAttachment / downloadAttachment / deleteAttachment.
// Download saves to a user-chosen location via NSSavePanel.
struct ReimbursementAttachmentsSheet: View {
    let apiClient: LinoAPIClient
    let claim: ReimbursementClaimDTO
    @Environment(\.dismiss) private var dismiss

    @State private var attachments: [AttachmentDTO] = []
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var busy = false
    @State private var errorMessage: String?

    private let ownerType = "reimbursement_claim"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在加载凭证…")
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    } else if attachments.isEmpty {
                        Text("这条报销还没有凭证。点右上角「上传」添加发票或收据。")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textTertiary)
                    } else {
                        ForEach(attachments) { attachment in
                            attachmentRow(attachment)
                        }
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.expense)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 520, height: 520)
        .background { BloomBackground(animated: false).opacity(0.9) }
        .task { await reload() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImport(result) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("报销凭证")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("\(claim.payer) · \(FinanceFormatter.money(claim.amount, currency: claim.currency))")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            Button {
                isImporting = true
            } label: {
                Label("上传", systemImage: "square.and.arrow.up")
                    .font(Theme.Font.caption())
            }
            .buttonStyle(.bordered)
            .disabled(busy)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func attachmentRow(_ attachment: AttachmentDTO) -> some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.contentType.contains("pdf") ? "doc.richtext" : "doc.text.image")
                .foregroundStyle(Theme.Color.brandEnd)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file))
                    .font(Theme.Font.badge())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            Button {
                Task { await download(attachment) }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .tint(Theme.Color.link)
            .disabled(busy)
            Button(role: .destructive) {
                Task { await delete(attachment) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .tint(Theme.Color.expense)
            .disabled(busy)
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            attachments = try await apiClient.listAttachments(ownerType: ownerType, ownerID: claim.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        busy = true
        defer { busy = false }
        do {
            let urls = try result.get()
            for url in urls {
                let attachment = try PendingClaimAttachment.from(url: url)
                _ = try await apiClient.uploadAttachment(
                    ownerType: ownerType,
                    ownerID: claim.id,
                    filename: attachment.filename,
                    contentType: attachment.contentType,
                    data: attachment.data
                )
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func download(_ attachment: AttachmentDTO) async {
        busy = true
        defer { busy = false }
        do {
            let data = try await apiClient.downloadAttachment(attachment.id)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = attachment.filename
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ attachment: AttachmentDTO) async {
        busy = true
        defer { busy = false }
        do {
            try await apiClient.deleteAttachment(attachment.id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#endif
