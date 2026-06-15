import SwiftUI

#if os(macOS)

// ReimbursementsScreen — v2.1.0 P2 报销 (macOS · glass · three-state).
//
// State machine collapsed to three single-user states (PROJECT_PLAN §5.7 D1):
//   pending (待回款) → received (已到账)   |   pending → abandoned (已放弃)
// Each state surfaces only its valid actions:
//   • pending → 确认到账 (opens ReceiveConfirmSheet) / 放弃
//   • received / abandoned → terminal, no actions
// "确认到账" is NEVER silent: the sheet forces the user to see and choose the
// receiving balance account, income category, and actual received date, and
// echoes "将 +¥X 进入 <账户>" before submitting (fixes the old "first matching
// account" guesswork that made net worth appear to jump out of nowhere — D-T3).
//
// Report chip collapses to three views (T6): 预计抵扣 (expected_net) /
// 已到账抵扣 (received_net) / 个人净支出 (personal_net).
struct ReimbursementsScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var reimModel: ReimbursementsModel

    @State private var showingNewClaim = false
    @State private var attachmentsClaim: ReimbursementClaimDTO?
    @State private var receivingClaim: ReimbursementClaimDTO?
    @State private var actionError: String?

    /// Display order of the three status columns.
    private let statusOrder = ["pending", "received", "abandoned"]

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
        .sheet(item: $receivingClaim) { claim in
            ReceiveConfirmSheet(
                claim: claim,
                accounts: reimModel.eligibleAccounts(for: claim, accounts: model.accounts),
                categories: reimModel.incomeCategories(model.categories)
            ) { account, category, date in
                try await reimModel.markReceived(
                    claim,
                    into: account,
                    incomeCategory: category,
                    receivedDate: date
                )
                await model.loadAccounts()
                await model.loadDashboard()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("报销")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("垫付、回款与个人净支出 · 待回款 / 已到账 / 已放弃")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            SubtleToolbarButton(title: "新建报销") { showingNewClaim = true }
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
                    HStack(spacing: 8) {
                        SelectableChip(title: "预计抵扣", isSelected: reimModel.reportView == "expected_net") {
                            setReportView("expected_net")
                        }
                        SelectableChip(title: "已到账抵扣", isSelected: reimModel.reportView == "received_net") {
                            setReportView("received_net")
                        }
                        SelectableChip(title: "个人净支出", isSelected: reimModel.reportView == "personal_net") {
                            setReportView("personal_net")
                        }
                    }
                }
                if let report = reimModel.report {
                    HStack(alignment: .top, spacing: 24) {
                        reportMetric("应报销支出", report.grossReimbursableExpenseCny, color: Theme.Color.textPrimary)
                        reportMetric("预计抵扣", report.expectedOffsetCny, color: Theme.Color.link)
                        reportMetric("已到账抵扣", report.receivedOffsetCny, color: Theme.Color.income)
                        reportMetric("个人净支出", report.selectedNetExpenseCny, color: Theme.Color.expenseStrong)
                    }
                    if !report.statusBreakdown.isEmpty {
                        Divider().overlay(Theme.Color.divider)
                        HStack(spacing: 8) {
                            ForEach(report.statusBreakdown) { row in
                                StatusBadge(
                                    text: "\(reimbursementStatusTitle(row.status)) \(row.claimCount)",
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
                StatusBadge(text: reimbursementStatusTitle(status), tone: tone(for: status))
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

    // Inline action chips (R3) — only the pending state has actions.
    //   确认到账=positive(绿，opens sheet) · 放弃=destructive(红)
    @ViewBuilder
    private func claimActions(_ claim: ReimbursementClaimDTO) -> some View {
        HStack(spacing: 8) {
            if claim.status == "pending" {
                TintedActionChip(title: "确认到账", tone: .positive) { receivingClaim = claim }
                TintedActionChip(title: "放弃", tone: .destructive) { runAbandon(claim) }
            }
            Spacer(minLength: 0)
            Button {
                attachmentsClaim = claim
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.link)
            }
            .buttonStyle(.plain)
            .help("凭证")
        }
        .font(Theme.Font.caption())
    }

    // MARK: - Actions

    private func runAbandon(_ claim: ReimbursementClaimDTO) {
        Task { await perform { try await reimModel.abandon(claim.id) } }
    }

    private func setReportView(_ view: String) {
        guard reimModel.reportView != view else { return }
        reimModel.reportView = view
        Task { await reimModel.reloadReport() }
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            actionError = nil
            try await work()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Status display (reimbursement-specific copy)

    private func reimbursementStatusTitle(_ status: String) -> String {
        switch status {
        case "pending": return "待回款"
        case "received": return "已到账"
        case "abandoned": return "已放弃"
        default: return status.financeStatusTitle
        }
    }

    private func tone(for status: String) -> StatusBadge.Tone {
        switch status {
        case "received": return .positive
        case "pending": return .pending
        case "abandoned": return .negative
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
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await reimModel.load() }
                }
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
                SubtleToolbarButton(title: "新建报销") { showingNewClaim = true }
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Receive confirmation sheet (D-T3: explicit account + category + date)

// ReceiveConfirmSheet — 确认到账 (glass modal).
//
// Forces the user to SEE and CHOOSE where the reimbursement lands before any
// balance moves: a balance-account picker (active, currency-matched), an income
// category picker, and the actual received date (default today). The footer
// echoes "将 +¥X 进入 <账户>" so there is no silent net-worth jump. Only on
// submit does the caller build the income entry and POST mark-received.
private struct ReceiveConfirmSheet: View {
    let claim: ReimbursementClaimDTO
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]
    let onConfirm: (AccountDTO, CategoryDTO, Date) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var receivedDate = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var selectedAccount: AccountDTO? {
        // 不回退第一个账户:未选即 nil → canSubmit 假 → 强制用户显式选并看见钱进哪(A4/T3 核心修复)
        guard let accountId else { return nil }
        return accounts.first { $0.id == accountId }
    }

    private var selectedCategory: CategoryDTO? {
        guard let categoryId else { return nil }
        return categories.first { $0.id == categoryId }
    }

    private var canSubmit: Bool {
        !isSubmitting && selectedAccount != nil && selectedCategory != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    claimSummary
                    field("入账账户") {
                        if accounts.isEmpty {
                            missingHint("没有匹配 \(claim.currency.rawValue) 的启用余额账户")
                        } else {
                            GlassMenuPicker(
                                label: selectedAccount?.name ?? "选择账户",
                                isPlaceholder: selectedAccount == nil
                            ) {
                                ForEach(accounts) { account in
                                    Button(account.name) { accountId = account.id }
                                }
                            }
                        }
                    }
                    field("收入分类") {
                        if categories.isEmpty {
                            missingHint("没有可用的收入分类")
                        } else {
                            GlassMenuPicker(
                                label: selectedCategory?.name ?? "选择分类",
                                isPlaceholder: selectedCategory == nil
                            ) {
                                ForEach(categories) { category in
                                    Button(category.name) { categoryId = category.id }
                                }
                            }
                        }
                    }
                    field("实际到账日期") {
                        DatePicker("", selection: $receivedDate, displayedComponents: .date)
                            .datePickerStyle(.field)
                            .labelsHidden()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .glassPanel(cornerRadius: Theme.Radius.button)
                    }
                    confirmationEcho
                }
                .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            footer
        }
        .frame(width: 520, height: 560)
        .background { BloomBackground(animated: false).opacity(0.9) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("确认到账")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("选择钱进入哪个账户，再确认到账")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var claimSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(claim.payer)
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("预计到账 \(FinanceFormatter.shortDate(claim.expectedDate))")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            AmountText(
                value: claim.amount,
                currency: claim.currency,
                font: Theme.Font.subtitle(.bold),
                color: Theme.Color.income
            )
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    @ViewBuilder
    private var confirmationEcho: some View {
        if let account = selectedAccount {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(Theme.Color.income)
                Text("将 ")
                    .foregroundStyle(Theme.Color.textSecondary)
                + Text("+\(FinanceFormatter.money(claim.amount, currency: claim.currency))")
                    .foregroundStyle(Theme.Color.income)
                + Text(" 进入「\(account.name)」")
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            .font(Theme.Font.caption(.medium))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: Theme.Radius.button)
        }
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
            PrimaryDarkButton("确认到账", isLoading: isSubmitting) {
                Task { await submit() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @MainActor
    private func submit() async {
        guard let account = selectedAccount, let category = selectedCategory else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await onConfirm(account, category, receivedDate)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func missingHint(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption())
            .foregroundStyle(Theme.Color.expense)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: Theme.Radius.button)
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

#endif
