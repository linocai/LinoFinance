import SwiftUI

#if os(macOS)

// AccountsScreen — D2 账户 (macOS, liquid glass). Replaces the P2 stub.
//
// Three groups by `type` (balance / credit / investment) rendered as glass
// cards, dual-currency original amounts side by side. Header carries 「新建账户」
// and 「对账」(the reconciliation entry point — balances change ONLY through
// reconciliation, so 对账 lives here, presenting the P4-owned ReconciliationScreen
// as a sheet). Credit cards show 额度 / 已用进度 / 账单日 / 还款日 / 最低还款.
// Investment accounts get a 「记当日盈亏」action.
//
// Contract: `init(model: AppModel)`. Owns its own @StateObject AccountsModel
// built on `model.apiClient` (nothing added to AppModel).

struct AccountsScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var accountsModel: AccountsModel

    @State private var formMode: AccountFormSheet.Mode?
    @State private var pnlAccount: AccountDTO?
    @State private var showReconciliation = false

    init(model: AppModel) {
        self.model = model
        _accountsModel = StateObject(wrappedValue: AccountsModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            switch accountsModel.state {
            case .idle, .loading where accountsModel.accounts.isEmpty:
                loadingState
            case .failed(let message):
                failedState(message)
            default:
                content
            }
        }
        .task { if accountsModel.accounts.isEmpty { await accountsModel.load() } }
        .sheet(item: $formMode) { mode in
            AccountFormSheet(model: accountsModel, mode: mode) {}
        }
        .sheet(item: $pnlAccount) { account in
            DailyPnLSheet(model: accountsModel, account: account) {}
        }
        .sheet(isPresented: $showReconciliation) {
            ReconciliationScreen(model: model)
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("账户")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("资金 / 信用 / 投资三类 · 双币种原币并排")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    showReconciliation = true
                } label: {
                    Label("对账", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
                Button {
                    formMode = .create
                } label: {
                    Label("新建账户", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if accountsModel.accounts.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 20) {
                if !accountsModel.balanceAccounts.isEmpty {
                    group(title: "资金账户", accounts: accountsModel.balanceAccounts) { account in
                        BalanceAccountRow(account: account, convertedCNY: accountsModel.convertedCNY(for: account))
                    } trailing: { account in
                        rowMenu(account)
                    }
                }
                if !accountsModel.investmentAccounts.isEmpty {
                    group(title: "投资账户", accounts: accountsModel.investmentAccounts) { account in
                        InvestmentAccountRow(account: account, convertedCNY: accountsModel.convertedCNY(for: account))
                    } trailing: { account in
                        HStack(spacing: 6) {
                            Button {
                                pnlAccount = account
                            } label: {
                                Label("记盈亏", systemImage: "plus.circle")
                                    .font(Theme.Font.caption(.medium))
                            }
                            .buttonStyle(.borderless)
                            rowMenu(account)
                        }
                    }
                }
                if !accountsModel.creditAccounts.isEmpty {
                    group(title: "信用账户", accounts: accountsModel.creditAccounts) { account in
                        CreditAccountRow(account: account)
                    } trailing: { account in
                        rowMenu(account)
                    }
                }
            }
        }
    }

    private func rowMenu(_ account: AccountDTO) -> some View {
        Menu {
            Button("编辑") { formMode = .edit(account) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

    // MARK: - Group card

    @ViewBuilder
    private func group<Row: View, Trailing: View>(
        title: String,
        accounts: [AccountDTO],
        @ViewBuilder row: @escaping (AccountDTO) -> Row,
        @ViewBuilder trailing: @escaping (AccountDTO) -> Trailing
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Text("\(accounts.count)")
                        .font(Theme.Font.badge(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.Color.textSecondary.opacity(0.08),
                                    in: Capsule())
                }
                VStack(spacing: 0) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 { Divider().overlay(Theme.Color.divider) }
                        HStack(alignment: .center, spacing: 10) {
                            row(account)
                            trailing(account)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("还没有账户")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("创建一个资金账户后就可以开始记账。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                Button("新建账户") { formMode = .create }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
    }

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载账户…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("账户加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                Button("重试") { Task { await accountsModel.load() } }
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Rows

private struct BalanceAccountRow: View {
    let account: AccountDTO
    let convertedCNY: DecimalValue?

    var body: some View {
        HStack(spacing: 12) {
            AccountIcon(systemImage: account.currency == .usd ? "dollarsign.circle" : "yensign.circle",
                        tint: Theme.Color.income)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    if account.status != "active" { StatusBadge(text: "归档", tone: .neutral) }
                    if !account.includeInNetWorth { StatusBadge(text: "不计净资产", tone: .warning) }
                }
                Text(subtitle)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: account.currentBalance, currency: account.currency,
                           font: Theme.Font.subtitle(.semibold), color: Theme.Color.textPrimary)
                if let convertedCNY {
                    AmountText(value: convertedCNY, currency: .cny,
                               font: Theme.Font.badge(), color: Theme.Color.textTertiary)
                }
            }
        }
    }

    private var subtitle: String {
        "资金账户 · \(account.currency.rawValue)" + (account.notes.map { " · \($0)" } ?? "")
    }
}

private struct InvestmentAccountRow: View {
    let account: AccountDTO
    let convertedCNY: DecimalValue?

    var body: some View {
        HStack(spacing: 12) {
            AccountIcon(systemImage: "chart.line.uptrend.xyaxis.circle", tint: Theme.Color.brandEnd)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    if account.status != "active" { StatusBadge(text: "归档", tone: .neutral) }
                }
                Text("投资账户 · \(account.currency.rawValue)")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: account.currentBalance, currency: account.currency,
                           font: Theme.Font.subtitle(.semibold), color: Theme.Color.brandEnd)
                if let convertedCNY {
                    AmountText(value: convertedCNY, currency: .cny,
                               font: Theme.Font.badge(), color: Theme.Color.textTertiary)
                }
            }
        }
    }
}

private struct CreditAccountRow: View {
    let account: AccountDTO

    /// 已用比例（current_liability / credit_limit），0…1。
    private var usage: Double? {
        guard let limit = account.creditLimit, limit.value > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: account.currentLiability.value)
            .dividing(by: NSDecimalNumber(decimal: limit.value)).doubleValue
        return max(0, min(1, ratio))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AccountIcon(systemImage: "creditcard", tint: Theme.Color.expense)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    if account.status != "active" { StatusBadge(text: "归档", tone: .neutral) }
                }
                Text(metaLine)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
                if let usage, let limit = account.creditLimit {
                    usageBar(usage: usage, limit: limit)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: DecimalValue(-account.currentLiability.value), currency: account.currency,
                           font: Theme.Font.subtitle(.semibold), color: Theme.Color.expense)
                if let minimum = account.minimumPayment {
                    Text("最低 \(account.currency.symbol)\(formatPlain(minimum.value))")
                        .font(Theme.Font.badge())
                        .monospacedDigit()
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var fill: some View {
        if let usage, usage >= 0.9 {
            Rectangle().fill(Theme.Color.expense)
        } else {
            Rectangle().fill(Theme.Color.brandGradient)
        }
    }

    @ViewBuilder
    private func usageBar(usage: Double, limit: DecimalValue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Color.textSecondary.opacity(0.12))
                    fill
                        .clipShape(Capsule())
                        .frame(width: max(4, geo.size.width * usage))
                }
            }
            .frame(height: 5)
            Text("已用 \(Int(usage * 100))% · 额度 \(account.currency.symbol)\(formatPlain(limit.value))")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .frame(maxWidth: 220)
        .padding(.top, 1)
    }

    private var metaLine: String {
        var parts: [String] = ["信用账户 · \(account.currency.rawValue)"]
        if let day = account.statementDay { parts.append("账单日 \(day)") }
        if let day = account.dueDay { parts.append("还款日 \(day)") }
        return parts.joined(separator: " · ")
    }

    private func formatPlain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

private struct AccountIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

extension AccountFormSheet.Mode: Identifiable {
    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let account): return "edit-\(account.id)"
        }
    }
}

#endif
