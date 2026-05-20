import SwiftUI
import UniformTypeIdentifiers

struct ReimbursementsView: View {
    @Bindable var environment: AppEnvironment
    @State private var confirmation: ConfirmAction?

    private let columns = [
        "reimbursable",
        "invoice_pending",
        "submitted",
        "approved",
        "waiting_received",
        "partial_received",
        "received",
        "rejected",
        "abandoned",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "报销", subtitle: "垫付、审批、到账和个人净支出")
            HStack(spacing: 10) {
                Button {
                    environment.beginNewReimbursement()
                } label: {
                    Label("新建报销", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }

            if environment.reimbursementsViewModel.claims.isEmpty {
                EmptyState(
                    title: "还没有报销",
                    message: "可从已确认记录生成报销，也可以在这里手动绑定一条记录。",
                    systemImage: "arrow.uturn.left.circle",
                    actionTitle: "新建报销",
                    action: environment.beginNewReimbursement
                )
            } else {
#if os(iOS)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(columns, id: \.self) { status in
                            ReimbursementColumn(
                                title: status.financeStatusTitle,
                                claims: environment.reimbursementsViewModel.claims.filter { $0.status == status },
                                select: { environment.inspectorSelection = .reimbursement($0) },
                                action: confirm
                            )
                        }
                    }
                }
#else
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(columns, id: \.self) { status in
                            ReimbursementColumn(
                                title: status.financeStatusTitle,
                                claims: environment.reimbursementsViewModel.claims.filter { $0.status == status },
                                select: { environment.inspectorSelection = .reimbursement($0) },
                                action: confirm
                            )
                            .frame(width: 260)
                        }
                    }
                    .padding(.vertical, 2)
                }
#endif
            }

            if let message = environment.reimbursementsViewModel.errorMessage {
                ErrorBanner(message: message)
            }
        }
        .padding(FinanceTokens.Spacing.page)
        .moduleFrame()
        .task {
            try? await environment.reimbursementsViewModel.refresh()
            try? await environment.reportsViewModel.refresh()
        }
        .alert(confirmation?.title ?? "确认操作", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), presenting: confirmation) { item in
            Button(item.confirmTitle, role: item.role) {
                item.action()
                confirmation = nil
            }
            Button("取消", role: .cancel) { confirmation = nil }
        } message: { item in
            Text(item.message)
        }
    }

    private func confirm(_ claim: ReimbursementClaimDTO, operation: String) {
        let copy: (String, String, String, ButtonRole?) = switch operation {
        case "submit":
            ("提交报销？", "状态会从可报销进入已提交。", "提交", nil)
        case "approve":
            ("批准报销？", "批准后会进入待到账流程。", "批准", nil)
        case "reject":
            ("拒绝报销？", "拒绝后将不再计入预计回款。", "拒绝", .destructive)
        case "abandon":
            ("放弃报销？", "放弃后这笔垫付会作为个人支出。", "放弃", .destructive)
        default:
            ("标记到账？", "到账会创建一条正式收入记录并影响账户余额。", "标记到账", nil)
        }
        confirmation = ConfirmAction(title: copy.0, message: copy.1, confirmTitle: copy.2, role: copy.3) {
            Task { await perform(claim, operation: operation) }
        }
    }

    private func perform(_ claim: ReimbursementClaimDTO, operation: String) async {
        do {
            switch operation {
            case "submit":
                try await environment.reimbursementsViewModel.submit(claim.id)
            case "approve":
                try await environment.reimbursementsViewModel.approve(claim.id)
            case "reject":
                try await environment.reimbursementsViewModel.reject(claim.id)
            case "abandon":
                try await environment.reimbursementsViewModel.abandon(claim.id)
            default:
                try await markReceived(claim)
            }
            try? await environment.dashboardViewModel.refresh()
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
            try? await environment.cashFlowViewModel.refresh()
            try? await environment.reportsViewModel.refresh()
        } catch {
            environment.reimbursementsViewModel.errorMessage = error.localizedDescription
            environment.lastErrorMessage = error.localizedDescription
        }
    }

    private func markReceived(_ claim: ReimbursementClaimDTO) async throws {
        guard let account = environment.accountsViewModel.accounts.balanceAccounts.first(where: { $0.currency == claim.currency }) else {
            throw APIError.badStatus(400, "标记到账需要一个 \(claim.currency.rawValue) 余额账户")
        }
        guard let category = environment.entriesViewModel.categories.first(where: { $0.type == .income }) else {
            throw APIError.badStatus(400, "标记到账需要至少一个收入分类")
        }
        let entry = EntryCreateRequest(
            title: "报销到账",
            date: Date(),
            status: .confirmed,
            note: claim.note,
            categoryLines: [
                EntryCategoryLineCreateRequest(
                    categoryId: category.id,
                    direction: .income,
                    amount: claim.amount,
                    currency: claim.currency,
                    exchangeRateId: claim.exchangeRateId,
                    convertedCnyAmount: claim.convertedCnyAmount,
                    note: claim.note
                )
            ],
            accountMovements: [
                AccountMovementCreateRequest(
                    accountId: account.id,
                    statementCycleId: nil,
                    movementType: .balanceIn,
                    amount: claim.amount,
                    currency: claim.currency,
                    exchangeRateId: claim.exchangeRateId,
                    convertedCnyAmount: claim.convertedCnyAmount,
                    note: claim.note
                )
            ]
        )
        let request = ReimbursementReceiveRequest(actualReceivedDate: Date(), receivedAccountId: account.id, entry: entry)
        try await environment.reimbursementsViewModel.markReceived(claim.id, request: request)
    }
}

private struct ReimbursementColumn: View {
    let title: String
    let claims: [ReimbursementClaimDTO]
    let select: (ReimbursementClaimDTO) -> Void
    let action: (ReimbursementClaimDTO, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(claims.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            ForEach(claims) { claim in
                Button {
                    select(claim)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            StatusTag(status: claim.status)
                            Spacer()
                            MoneyText(amount: claim.amount, currency: claim.currency, convertedCNY: claim.convertedCnyAmount, prominence: .headline)
                        }
                        Text("\(claim.payer) · 预计 \(FinanceFormatter.shortDate(claim.expectedDate))")
                            .font(.caption)
                            .foregroundStyle(FinanceTokens.Text.secondary)
                        HStack {
                            if claim.status == "reimbursable" || claim.status == "invoice_pending" {
                                Button("提交") { action(claim, "submit") }
                            }
                            if claim.status == "submitted" {
                                Button("批准") { action(claim, "approve") }
                                Button("拒绝") { action(claim, "reject") }
                            }
                            if ["approved", "waiting_received", "partial_received"].contains(claim.status) {
                                Button("到账") { action(claim, "receive") }
                            }
                            if !["received", "rejected", "abandoned"].contains(claim.status) {
                                Button("放弃") { action(claim, "abandon") }
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(12)
                    .glassBackground(radius: FinanceTokens.Radius.sm)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(FinanceTokens.Stroke.soft)
        .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.sm))
    }
}

struct NewReimbursementClaimSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var entryId: String?
    @State private var lineId: String?
    @State private var payer = "company"
    @State private var expectedDate = Date()
    @State private var note = ""
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var isImportingAttachments = false
    @State private var errorMessage: String?

    private var selectedEntry: EntryDTO? {
        guard let entryId else { return environment.entriesViewModel.entries.first }
        return environment.entriesViewModel.entries.first { $0.id == entryId }
    }

    private var selectedLine: EntryCategoryLineDTO? {
        let lines = selectedEntry?.categoryLines ?? []
        guard let lineId else { return lines.first }
        return lines.first { $0.id == lineId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建报销")
                .font(.title2.weight(.semibold))
            Form {
                Picker("原始记录", selection: entrySelection) {
                    ForEach(environment.entriesViewModel.entries) { entry in
                        Text(entry.title).tag(Optional(entry.id))
                    }
                }
                Picker("分类明细", selection: lineSelection) {
                    ForEach(selectedEntry?.categoryLines ?? []) { line in
                        Text("\(line.direction.title) · \(FinanceFormatter.money(line.amount, currency: line.currency))")
                            .tag(Optional(line.id))
                    }
                }
                TextField("付款方", text: $payer)
                DatePicker("预计到账", selection: $expectedDate, displayedComponents: .date)
                TextField("备注", text: $note)
                Button {
                    isImportingAttachments = true
                } label: {
                    Label("选择凭证文件", systemImage: "paperclip")
                }
                if !pendingAttachments.isEmpty {
                    ForEach(pendingAttachments) { attachment in
                        HStack {
                            Image(systemName: attachment.contentType.contains("pdf") ? "doc.richtext" : "doc")
                                .foregroundStyle(FinanceTokens.Brand.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.filename)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(attachment.formattedSize)
                                    .font(.caption2)
                                    .foregroundStyle(FinanceTokens.Text.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                pendingAttachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            HStack {
                Spacer()
                Button("取消") { environment.isShowingNewReimbursementSheet = false }
                Button("创建") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedEntry == nil || selectedLine == nil)
            }
        }
        .padding(22)
        .task {
            try? await environment.entriesViewModel.refresh()
        }
        .fileImporter(
            isPresented: $isImportingAttachments,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            do {
                pendingAttachments.append(contentsOf: try result.get().map(PendingAttachment.from(url:)))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var entrySelection: Binding<String?> {
        Binding(get: { entryId ?? environment.entriesViewModel.entries.first?.id }, set: { entryId = $0; lineId = nil })
    }

    private var lineSelection: Binding<String?> {
        Binding(get: { lineId ?? selectedEntry?.categoryLines.first?.id }, set: { lineId = $0 })
    }

    private func submit() async {
        guard let entry = selectedEntry, let line = selectedLine else { return }
        let request = ReimbursementClaimCreateRequest(
            linkedEntryId: entry.id,
            linkedEntryLineId: line.id,
            amount: line.amount,
            currency: line.currency,
            exchangeRateId: line.exchangeRateId,
            convertedCnyAmount: line.convertedCnyAmount,
            payer: payer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "company" : payer,
            expectedDate: expectedDate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            let claim = try await environment.reimbursementsViewModel.create(request)
            for attachment in pendingAttachments {
                try await environment.attachmentViewModel.upload(
                    ownerType: "reimbursement_claim",
                    ownerID: claim.id,
                    filename: attachment.filename,
                    contentType: attachment.contentType,
                    data: attachment.data
                )
            }
            try? await environment.reportsViewModel.refresh()
            environment.isShowingNewReimbursementSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
