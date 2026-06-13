import SwiftUI

#if os(macOS)

// ReimbursementsScreen — D6 报销 (macOS · glass · state machine + 凭证 attachments).
//
// State machine (plan §D6):
//   reimbursable → invoice_pending → submitted → approved → waiting_received → received
//   (+ partial_received / rejected / abandoned)
// Each status surfaces only its valid actions (StatusBadge shows the state):
//   • reimbursable / invoice_pending      → 提交
//   • submitted                            → 批准 / 拒绝
//   • approved / waiting_received / 部分到账 → 标记到账
//   • any non-terminal                     → 放弃
//
// Data (all real client methods):
//   listReimbursementClaims / createReimbursementClaim
//   submit/approve/reject/abandon ReimbursementClaim
//   markReimbursementReceived (builds an income settlement entry, see model)
//   reimbursementReport(view:)  — personal-net vs all
//   listAttachments / uploadAttachment / downloadAttachment / deleteAttachment
struct ReimbursementsScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var reimModel: ReimbursementsModel

    @State private var pendingConfirm: PendingConfirm?
    @State private var showingNewClaim = false
    @State private var attachmentsClaim: ReimbursementClaimDTO?
    @State private var actionError: String?

    /// Display order of status columns.
    private let statusOrder = [
        "reimbursable", "invoice_pending", "submitted", "approved",
        "waiting_received", "partial_received", "received", "rejected", "abandoned",
    ]

    init(model: AppModel) {
        self.model = model
        _reimModel = StateObject(wrappedValue: ReimbursementsModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            switch reimModel.state {
            case .idle, .loading:
                loadingState
            case .failed(let message):
                failedState(message)
            case .loaded:
                reportCard
                if reimModel.claims.isEmpty {
                    emptyState
                } else {
                    claimColumns
                }
            }
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
            }
        }
        .task {
            if reimModel.claims.isEmpty { await reimModel.load() }
            if model.accounts.isEmpty { await model.loadAccounts() }
            if model.categories.isEmpty { await model.loadCategories() }
        }
        .sheet(isPresented: $showingNewClaim) {
            NewReimbursementClaimSheet(model: model, reimModel: reimModel)
        }
        .sheet(item: $attachmentsClaim) { claim in
            ReimbursementAttachmentsSheet(apiClient: model.apiClient, claim: claim)
        }
        .alert(pendingConfirm?.title ?? "确认操作", isPresented: confirmBinding, presenting: pendingConfirm) { item in
            Button(item.confirmTitle, role: item.role) {
                Task { await item.run() }
            }
            Button("取消", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("报销")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("垫付、审批、到账与个人净支出 · 按状态流转")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            PrimaryActionButton(title: "新建报销", systemImage: "plus", compact: true) {
                showingNewClaim = true
            }
            .frame(width: 150)
        }
    }

    // MARK: - Report summary

    @ViewBuilder
    private var reportCard: some View {
        GlassCard(tint: Theme.Color.brandEnd) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("报销汇总")
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Picker("", selection: $reimModel.reportView) {
                        Text("个人净额").tag("personal_net")
                        Text("全部").tag("all")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .onChange(of: reimModel.reportView) { _, _ in
                        Task { await reimModel.reloadReport() }
                    }
                }
                if let report = reimModel.report {
                    HStack(alignment: .top, spacing: 24) {
                        reportMetric("应报销支出", report.grossReimbursableExpenseCny, color: Theme.Color.textPrimary)
                        reportMetric("已到账抵扣", report.receivedOffsetCny, color: Theme.Color.income)
                        reportMetric("预计抵扣", report.expectedOffsetCny, color: Theme.Color.link)
                        reportMetric("个人净支出", report.personalNetExpenseCny, color: Theme.Color.expenseStrong)
                    }
                    if !report.statusBreakdown.isEmpty {
                        Divider().overlay(Theme.Color.divider)
                        HStack(spacing: 8) {
                            ForEach(report.statusBreakdown) { row in
                                StatusBadge(
                                    text: "\(row.status.financeStatusTitle) \(row.claimCount)",
                                    tone: tone(for: row.status)
                                )
                            }
                        }
                    }
                } else {
                    Text("暂无报销汇总数据。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    private func reportMetric(_ label: String, _ value: DecimalValue, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Font.badge(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)
            AmountText(value: value, currency: .cny, font: Theme.Font.subtitle(.bold), color: color)
        }
    }

    // MARK: - Claim columns

    private var claimColumns: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(populatedStatuses, id: \.self) { status in
                    claimColumn(status)
                        .frame(width: 280)
                }
            }
            .padding(.bottom, 6)
        }
    }

    /// Only statuses that actually have claims (in canonical order).
    private var populatedStatuses: [String] {
        let present = Set(reimModel.claims.map { $0.status })
        return statusOrder.filter { present.contains($0) }
    }

    private func claimColumn(_ status: String) -> some View {
        let claims = reimModel.claims.filter { $0.status == status }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(text: status.financeStatusTitle, tone: tone(for: status))
                Spacer()
                Text("\(claims.count)")
                    .font(Theme.Font.caption(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            ForEach(claims) { claim in
                claimCard(claim)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: Theme.Radius.card)
    }

    private func claimCard(_ claim: ReimbursementClaimDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(claim.payer)
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                AmountText(
                    value: claim.amount,
                    currency: claim.currency,
                    font: Theme.Font.subtitle(.semibold),
                    color: Theme.Color.textPrimary
                )
            }
            Text("预计到账 \(FinanceFormatter.shortDate(claim.expectedDate))")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
            if let note = claim.note, !note.isEmpty {
                Text(note)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
                    .lineLimit(2)
            }
            claimActions(claim)
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    @ViewBuilder
    private func claimActions(_ claim: ReimbursementClaimDTO) -> some View {
        HStack(spacing: 8) {
            if claim.status == "reimbursable" || claim.status == "invoice_pending" {
                actionButton("提交") { confirmSubmit(claim) }
            }
            if claim.status == "submitted" {
                actionButton("批准") { confirmApprove(claim) }
                actionButton("拒绝", destructive: true) { confirmReject(claim) }
            }
            if ["approved", "waiting_received", "partial_received"].contains(claim.status) {
                actionButton("标记到账") { confirmReceive(claim) }
            }
            if !["received", "rejected", "abandoned"].contains(claim.status) {
                actionButton("放弃", destructive: true) { confirmAbandon(claim) }
            }
            Spacer(minLength: 0)
            Button {
                attachmentsClaim = claim
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .tint(Theme.Color.link)
            .help("凭证")
        }
        .font(Theme.Font.caption())
    }

    private func actionButton(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .tint(destructive ? Theme.Color.expense : Theme.Color.link)
    }

    // MARK: - Confirmations

    private func confirmSubmit(_ claim: ReimbursementClaimDTO) {
        pendingConfirm = PendingConfirm(
            title: "提交报销？",
            message: "状态会从「\(claim.status.financeStatusTitle)」进入「已提交」。",
            confirmTitle: "提交",
            role: nil
        ) { await perform { try await reimModel.submit(claim.id) } }
    }

    private func confirmApprove(_ claim: ReimbursementClaimDTO) {
        pendingConfirm = PendingConfirm(
            title: "批准报销？",
            message: "批准后会进入待到账流程。",
            confirmTitle: "批准",
            role: nil
        ) { await perform { try await reimModel.approve(claim.id) } }
    }

    private func confirmReject(_ claim: ReimbursementClaimDTO) {
        pendingConfirm = PendingConfirm(
            title: "拒绝报销？",
            message: "拒绝后将不再计入预计回款。",
            confirmTitle: "拒绝",
            role: .destructive
        ) { await perform { try await reimModel.reject(claim.id) } }
    }

    private func confirmAbandon(_ claim: ReimbursementClaimDTO) {
        pendingConfirm = PendingConfirm(
            title: "放弃报销？",
            message: "放弃后这笔垫付会作为个人支出。",
            confirmTitle: "放弃",
            role: .destructive
        ) { await perform { try await reimModel.abandon(claim.id) } }
    }

    private func confirmReceive(_ claim: ReimbursementClaimDTO) {
        let accountName = reimModel.receivingAccountName(for: claim, accounts: model.accounts) ?? "<无匹配账户>"
        let amount = FinanceFormatter.money(claim.amount, currency: claim.currency)
        pendingConfirm = PendingConfirm(
            title: "标记到账？",
            message: "会创建一条已确认的收入记账，并把 \(amount) 计入余额账户「\(accountName)」。继续吗？",
            confirmTitle: "标记到账",
            role: nil
        ) {
            await perform {
                try await reimModel.markReceived(claim, accounts: model.accounts, categories: model.categories)
                await model.loadAccounts()
                await model.loadDashboard()
            }
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            actionError = nil
            try await work()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } })
    }

    // MARK: - Status → tone

    private func tone(for status: String) -> StatusBadge.Tone {
        switch status {
        case "received": return .positive
        case "reimbursable", "submitted", "waiting_received", "approved", "partial_received": return .pending
        case "invoice_pending": return .warning
        case "rejected", "abandoned": return .negative
        default: return .neutral
        }
    }

    // MARK: - States

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载报销…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("报销加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                Button("重试") { Task { await reimModel.load() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("还没有报销", systemImage: "arrow.uturn.left.circle")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("从一条已确认的记账明细生成报销，跟踪垫付到回款的全过程。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
                Button("新建报销") { showingNewClaim = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Confirmation payload

private struct PendingConfirm: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let role: ButtonRole?
    let run: () async -> Void
}

#endif
