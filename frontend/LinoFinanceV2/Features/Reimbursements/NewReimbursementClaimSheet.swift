import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)

// NewReimbursementClaimSheet — D6 新建报销 (glass modal).
//
// A claim links onto an EXISTING confirmed entry + one of its category lines
// (amount/currency/rate inherited from the line — see ReimbursementsModel.createClaim).
// Optionally attaches invoice/receipt files (uploaded to the new claim's id after
// it is created, via uploadAttachment owner_type=reimbursement_claim).
struct NewReimbursementClaimSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var reimModel: ReimbursementsModel
    @Environment(\.dismiss) private var dismiss

    @State private var entryId: String?
    @State private var lineId: String?
    @State private var payer = "company"
    @State private var expectedDate = Date()
    @State private var note = ""
    @State private var pendingAttachments: [PendingClaimAttachment] = []
    @State private var isImporting = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var selectedEntry: EntryDTO? {
        guard let entryId else { return reimModel.entries.first }
        return reimModel.entries.first { $0.id == entryId }
    }

    private var selectedLine: EntryCategoryLineDTO? {
        let lines = selectedEntry?.categoryLines ?? []
        guard let lineId else { return lines.first }
        return lines.first { $0.id == lineId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("原始记录") {
                        GlassMenuPicker(
                            label: selectedEntry?.title ?? "无已确认记录",
                            isPlaceholder: selectedEntry == nil,
                            disabled: reimModel.entries.isEmpty
                        ) {
                            ForEach(reimModel.entries) { entry in
                                Button(entry.title) { entryBinding.wrappedValue = entry.id }
                            }
                        }
                    }
                    field("分类明细") {
                        GlassMenuPicker(
                            label: selectedLine.map { "\($0.direction.title) · \(FinanceFormatter.money($0.amount, currency: $0.currency))" } ?? "无可选明细",
                            isPlaceholder: selectedLine == nil,
                            disabled: selectedEntry == nil
                        ) {
                            ForEach(selectedEntry?.categoryLines ?? []) { line in
                                Button("\(line.direction.title) · \(FinanceFormatter.money(line.amount, currency: line.currency))") {
                                    lineBinding.wrappedValue = line.id
                                }
                            }
                        }
                    }
                    field("付款方") {
                        TextField("如：公司", text: $payer)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("预计到账") {
                        DatePicker("", selection: $expectedDate, displayedComponents: .date)
                            .datePickerStyle(.field)
                            .labelsHidden()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .glassPanel(cornerRadius: Theme.Radius.button)
                    }
                    field("备注（可选）") {
                        TextField("补充说明", text: $note)
                            .textFieldStyle(.roundedBorder)
                    }
                    attachmentsSection
                }
                .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            footer
        }
        .frame(width: 560, height: 640)
        .background { BloomBackground(animated: false).opacity(0.9) }
        .task {
            if reimModel.entries.isEmpty { await reimModel.loadEntries() }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            do {
                pendingAttachments.append(contentsOf: try result.get().map(PendingClaimAttachment.from(url:)))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.left.circle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("新建报销")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("绑定一条已确认记账明细")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("凭证（发票/收据，可选）")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                SubtleToolbarButton(title: "选择文件", systemImage: "paperclip") {
                    isImporting = true
                }
            }
            ForEach(pendingAttachments) { attachment in
                HStack(spacing: 8) {
                    Image(systemName: attachment.contentType.contains("pdf") ? "doc.richtext" : "doc")
                        .foregroundStyle(Theme.Color.brandEnd)
                    Text(attachment.filename)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(attachment.formattedSize)
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textTertiary)
                    Button {
                        pendingAttachments.removeAll { $0.id == attachment.id }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(Theme.Color.expense)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            SubtleTextButton("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            PrimaryDarkButton("创建", isLoading: isSubmitting) {
                Task { await submit() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting || selectedEntry == nil || selectedLine == nil)
            .opacity((isSubmitting || selectedEntry == nil || selectedLine == nil) ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var entryBinding: Binding<String?> {
        Binding(
            get: { entryId ?? reimModel.entries.first?.id },
            set: { entryId = $0; lineId = nil }
        )
    }

    private var lineBinding: Binding<String?> {
        Binding(
            get: { lineId ?? selectedEntry?.categoryLines.first?.id },
            set: { lineId = $0 }
        )
    }

    @MainActor
    private func submit() async {
        guard let entry = selectedEntry, let line = selectedLine else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let claim = try await reimModel.createClaim(
                entry: entry,
                line: line,
                payer: payer,
                expectedDate: expectedDate,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
            )
            for attachment in pendingAttachments {
                _ = try await model.apiClient.uploadAttachment(
                    ownerType: "reimbursement_claim",
                    ownerID: claim.id,
                    filename: attachment.filename,
                    contentType: attachment.contentType,
                    data: attachment.data
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            content()
        }
    }
}

// MARK: - Pending attachment (read once at pick time)

struct PendingClaimAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let contentType: String
    let data: Data

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    static func from(url: URL) throws -> PendingClaimAttachment {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return PendingClaimAttachment(filename: url.lastPathComponent, contentType: type, data: data)
    }
}

#endif
