import SwiftUI

#if os(macOS)

// AccountDetailScreen — v2.3.0 P3 单账户流水专屏 (D6=甲, macOS, liquid glass).
//
// Presented as a sheet when an account row is tapped (the tap used to open the
// edit sheet; now it opens this detail, and 编辑 moves to a header button here).
// Sections, top to bottom:
//   • 账户头        — name + balance / credit liability + 编辑 button
//   • 历史流水      — confirmed-entry movements on this account (newest first)
//   • 未来现金流    — pending cash flow items on this account
//   • 信用账单周期  — statement cycles (credit accounts only)
//   • 分期排期      — each plan's ALL periods + REAL settled progress (P3 fix)
//
// Data = pure front-end local filtering (AccountDetailModel, D5=甲).
struct AccountDetailScreen: View {
    @ObservedObject var accountsModel: AccountsModel
    @StateObject private var detail: AccountDetailModel
    let account: AccountDTO
    var onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(accountsModel: AccountsModel, account: AccountDTO, onEdit: @escaping () -> Void) {
        self.accountsModel = accountsModel
        self.account = account
        self.onEdit = onEdit
        _detail = StateObject(wrappedValue: AccountDetailModel(account: account, apiClient: accountsModel.apiClientForDetail))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    accountHeaderCard
                    switch detail.state {
                    case .idle, .loading:
                        loadingCard
                    case .failed(let message):
                        failedCard(message)
                    case .loaded:
                        loadedSections
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 640, height: 680)
        .background { BloomBackground(animated: false).opacity(0.9) }
        .task { await detail.load() }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: accountIcon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
                Text(accountSubtitle).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            SubtleToolbarButton(title: "编辑账户", systemImage: "pencil") {
                dismiss()
                onEdit()
            }
            SubtleTextButton("关闭") { dismiss() }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Account header card

    private var accountHeaderCard: some View {
        GlassCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.type == .credit ? "当前欠款" : "当前余额")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                    if account.type == .credit {
                        AmountText(value: DecimalValue(-account.currentLiability.value), currency: account.currency,
                                   font: Theme.Font.cardNumber(), color: Theme.Color.expense)
                    } else {
                        AmountText(value: account.currentBalance, currency: account.currency,
                                   font: Theme.Font.cardNumber(),
                                   color: account.type == .investment ? Theme.Color.brandEnd : Theme.Color.textPrimary)
                    }
                }
                Spacer()
                if account.type == .credit, let limit = account.creditLimit {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("额度").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                        AmountText(value: limit, currency: account.currency,
                                   font: Theme.Font.subtitle(.semibold), color: Theme.Color.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Loaded sections

    @ViewBuilder
    private var loadedSections: some View {
        movementsSection
        futureCashFlowSection
        if account.type == .credit {
            statementCyclesSection
            installmentsSection
        }
    }

    private var movementsSection: some View {
        section(title: "历史流水", count: detail.movements.count, emptyHint: "该账户暂无已确认流水。") {
            VStack(spacing: 0) {
                ForEach(Array(detail.movements.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(Theme.Color.divider) }
                    movementRow(row).padding(.vertical, 10)
                }
            }
        }
    }

    private func movementRow(_ row: AccountDetailModel.MovementRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: movementSymbol(row.movementType))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(movementTint(row.movementType))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(Theme.Font.body(.semibold)).foregroundStyle(Theme.Color.textPrimary).lineLimit(1)
                Text("\(FinanceFormatter.shortDate(row.date)) · \(movementLabel(row.movementType))")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer(minLength: 8)
            AmountText(value: row.amount, currency: row.currency,
                       font: Theme.Font.subtitle(.semibold), color: movementTint(row.movementType))
        }
    }

    private var futureCashFlowSection: some View {
        section(title: "未来现金流", count: detail.futureCashFlows.count, emptyHint: "该账户暂无未来现金流。") {
            VStack(spacing: 0) {
                ForEach(Array(detail.futureCashFlows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Theme.Color.divider) }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.title).font(Theme.Font.body(.semibold)).foregroundStyle(Theme.Color.textPrimary).lineLimit(1)
                                StatusBadge(text: item.statusTitle, tone: item.statusTone)
                                StatusBadge(text: CashFlowType.title(item.cashFlowType), tone: .neutral)
                            }
                            Text(FinanceFormatter.shortDate(item.expectedDate))
                                .font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                        }
                        Spacer(minLength: 8)
                        AmountText(value: item.amount, currency: item.currency,
                                   font: Theme.Font.subtitle(.semibold), color: Theme.Color.textSecondary)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var statementCyclesSection: some View {
        section(title: "信用账单周期", count: detail.statementCycles.count, emptyHint: "该账户暂无账单周期。") {
            VStack(spacing: 0) {
                ForEach(Array(detail.statementCycles.enumerated()), id: \.element.id) { index, cycle in
                    if index > 0 { Divider().overlay(Theme.Color.divider) }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("账单 \(FinanceFormatter.shortDate(cycle.statementDate))")
                                    .font(Theme.Font.body(.semibold)).foregroundStyle(Theme.Color.textPrimary)
                                StatusBadge(text: cycle.status.financeStatusTitle, tone: .neutral)
                            }
                            Text("还款日 \(FinanceFormatter.shortDate(cycle.dueDate)) · 剩余 \(FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency))")
                                .font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                        }
                        Spacer(minLength: 8)
                        AmountText(value: cycle.statementAmount, currency: cycle.currency,
                                   font: Theme.Font.subtitle(.semibold), color: Theme.Color.textPrimary)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var installmentsSection: some View {
        section(title: "分期排期", count: detail.installments.count, emptyHint: "该账户暂无分期。") {
            VStack(spacing: 14) {
                ForEach(detail.installments) { progress in
                    installmentBlock(progress)
                }
            }
        }
    }

    private func installmentBlock(_ progress: AccountDetailModel.InstallmentProgress) -> some View {
        let plan = progress.plan
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("分期 · \(FinanceFormatter.shortDate(plan.startDate))")
                    .font(Theme.Font.body(.semibold)).foregroundStyle(Theme.Color.textPrimary)
                StatusBadge(text: plan.status.financeStatusTitle, tone: .neutral)
                Spacer()
                // REAL progress (P3 fix): 已还 = settled period count, NOT generatedCashFlowCount.
                Text("已还 \(progress.settledCount)/共 \(plan.numberOfPayments) 期")
                    .font(Theme.Font.caption(.medium).monospacedDigit())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            // ALL periods listed (fixes "只跳到下一期").
            VStack(spacing: 0) {
                ForEach(Array(progress.periods.enumerated()), id: \.element.id) { index, period in
                    if index > 0 { Divider().overlay(Theme.Color.divider) }
                    HStack(spacing: 10) {
                        Text("第 \(index + 1) 期")
                            .font(Theme.Font.caption(.medium).monospacedDigit())
                            .foregroundStyle(Theme.Color.textTertiary)
                            .frame(width: 52, alignment: .leading)
                        Text(FinanceFormatter.shortDate(period.expectedDate))
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                        StatusBadge(text: period.statusTitle, tone: period.statusTone)
                        Spacer(minLength: 8)
                        AmountText(value: period.amount, currency: period.currency,
                                   font: Theme.Font.caption(.semibold), color: Theme.Color.textSecondary)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    // MARK: - Shared section scaffold

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        count: Int,
        emptyHint: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(Theme.Font.subtitle(.semibold)).foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Text("\(count)")
                        .font(Theme.Font.badge(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.Color.textSecondary.opacity(0.08), in: Capsule())
                }
                if count == 0 {
                    Text(emptyHint).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textTertiary)
                } else {
                    content()
                }
            }
        }
    }

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载账户流水…").font(Theme.Font.body()).foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedCard(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("流水加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold)).foregroundStyle(Theme.Color.expense)
                Text(message).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await detail.load() }
                }
            }
        }
    }

    // MARK: - Presentation helpers

    private var accountIcon: String {
        switch account.type {
        case .credit: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis.circle"
        case .balance: account.currency == .usd ? "dollarsign.circle" : "yensign.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var accountSubtitle: String {
        let typeLabel: String
        switch account.type {
        case .credit: typeLabel = "信用账户"
        case .investment: typeLabel = "投资账户"
        case .balance: typeLabel = "资金账户"
        case .unknown: typeLabel = "未知类型账户"
        }
        return "\(typeLabel) · \(account.currency.rawValue)"
    }

    private func movementSymbol(_ type: MovementType) -> String {
        switch type {
        case .balanceIn, .transferIn: "arrow.down.circle.fill"
        case .balanceOut, .transferOut: "arrow.up.circle.fill"
        case .creditCharge: "creditcard.circle.fill"
        case .creditRepayment: "arrow.left.arrow.right.circle.fill"
        }
    }

    private func movementTint(_ type: MovementType) -> Color {
        switch type {
        case .balanceIn, .transferIn: Theme.Color.income
        case .balanceOut, .creditCharge: Theme.Color.expense
        case .transferOut, .creditRepayment: Theme.Color.textSecondary
        }
    }

    private func movementLabel(_ type: MovementType) -> String {
        switch type {
        case .balanceIn: "进账"
        case .balanceOut: "出账"
        case .creditCharge: "信用消费"
        case .creditRepayment: "信用还款"
        case .transferIn: "转入"
        case .transferOut: "转出"
        }
    }
}

#endif
