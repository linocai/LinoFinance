import SwiftUI

#if os(iOS)

// AccountsIOSView — D2 账户 (iOS · narrow, liquid glass).
//
// Mirrors the macOS AccountsScreen data semantics (AccountsModel: three groups by
// type 资金 / 投资 / 信用, dual-currency original amount + CNY approximation,
// credit-card 额度/已用进度/账单日/还款日/最低还款, investment 记盈亏 chip) but
// re-flowed to the phone column. Read-only browsing + 记盈亏; create/edit forms are
// macOS-only sheets (iOS 版后续). Balances change only through reconciliation.

struct AccountsIOSView: View {
    @ObservedObject var model: AppModel
    @StateObject private var accountsModel: AccountsModel

    @State private var pnlAccount: AccountDTO?

    init(model: AppModel) {
        self.model = model
        _accountsModel = StateObject(wrappedValue: AccountsModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .sheet(item: $pnlAccount) { account in
            DailyPnLSheetIOS(model: accountsModel, account: account) {
                // 记盈亏已自刷 accountsModel；同步刷 AppModel.dashboard 让总览跟上。
                Task { await model.refreshAll() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("账户")
                .font(Theme.Font.pageTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Text("资金 / 投资 / 信用三类 · 双币种原币")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if accountsModel.accounts.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if !accountsModel.balanceAccounts.isEmpty {
                    group(title: "资金账户", count: accountsModel.balanceAccounts.count) {
                        rows(accountsModel.balanceAccounts) { account in
                            BalanceRowIOS(account: account, convertedCNY: accountsModel.convertedCNY(for: account))
                        }
                    }
                }
                if !accountsModel.investmentAccounts.isEmpty {
                    group(title: "投资账户", count: accountsModel.investmentAccounts.count) {
                        rows(accountsModel.investmentAccounts) { account in
                            VStack(alignment: .leading, spacing: 8) {
                                InvestmentRowIOS(account: account, convertedCNY: accountsModel.convertedCNY(for: account))
                                HStack {
                                    Spacer()
                                    TintedActionChip(title: "记盈亏", tone: .brand) { pnlAccount = account }
                                }
                            }
                        }
                    }
                }
                if !accountsModel.creditAccounts.isEmpty {
                    group(title: "信用账户", count: accountsModel.creditAccounts.count) {
                        rows(accountsModel.creditAccounts) { account in
                            CreditRowIOS(account: account)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Group card + hairline-divided rows

    @ViewBuilder
    private func group<Content: View>(title: String, count: Int, @ViewBuilder content: @escaping () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Text("\(count)")
                        .font(Theme.Font.badge(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.Color.textSecondary.opacity(0.08), in: Capsule())
                }
                content()
            }
        }
    }

    @ViewBuilder
    private func rows<Row: View>(_ accounts: [AccountDTO], @ViewBuilder row: @escaping (AccountDTO) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { Divider().overlay(Theme.Color.divider) }
                row(account)
                    .padding(.vertical, 10)
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
                Text("在 macOS 端创建账户后即可在此查看。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
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
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await accountsModel.load() }
                }
            }
        }
    }
}

// MARK: - Rows (iOS-compact mirrors of the macOS AccountsScreen rows)

private struct AccountIconIOS: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct BalanceRowIOS: View {
    let account: AccountDTO
    let convertedCNY: DecimalValue?

    var body: some View {
        HStack(spacing: 11) {
            AccountIconIOS(systemImage: account.currency == .usd ? "dollarsign.circle" : "yensign.circle",
                           tint: Theme.Color.income)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    if account.status != "active" { StatusBadge(text: "归档", tone: .neutral) }
                    if !account.includeInNetWorth { StatusBadge(text: "不计净资产", tone: .warning) }
                }
                Text("资金账户 · \(account.currency.rawValue)")
                    .font(Theme.Font.badge())
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
}

private struct InvestmentRowIOS: View {
    let account: AccountDTO
    let convertedCNY: DecimalValue?

    var body: some View {
        HStack(spacing: 11) {
            AccountIconIOS(systemImage: "chart.line.uptrend.xyaxis.circle", tint: Theme.Color.brandEnd)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    if account.status != "active" { StatusBadge(text: "归档", tone: .neutral) }
                }
                Text("投资账户 · \(account.currency.rawValue)")
                    .font(Theme.Font.badge())
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

private struct CreditRowIOS: View {
    let account: AccountDTO

    private var usage: Double? {
        guard let limit = account.creditLimit, limit.value > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: account.currentLiability.value)
            .dividing(by: NSDecimalNumber(decimal: limit.value)).doubleValue
        return max(0, min(1, ratio))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 11) {
                AccountIconIOS(systemImage: "creditcard", tint: Theme.Color.expense)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(account.name)
                            .font(Theme.Font.body(.semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                        if account.status != "active" { StatusBadge(text: "归档", tone: .neutral) }
                    }
                    Text(metaLine)
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
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
            if let usage, let limit = account.creditLimit {
                usageBar(usage: usage, limit: limit)
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
        .padding(.leading, 41)   // align under the name column
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

// MARK: - 记当日盈亏 (iOS sheet)
//
// Mirrors macOS DailyPnLSheet: input = the account's CURRENT balance, the backend
// computes today's delta and adjusts the balance. NavigationStack chrome with a
// 取消 / 记录 toolbar so it reads as a native iOS sheet.

private struct DailyPnLSheetIOS: View {
    @ObservedObject var model: AccountsModel
    let account: AccountDTO
    /// 记盈亏成功后回调，让宿主刷新 AppModel.dashboard（总览）。
    var onRecorded: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var newBalanceText = ""
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var parsedNewBalance: Decimal? {
        Decimal(string: newBalanceText.trimmingCharacters(in: .whitespaces))
    }

    private var delta: Decimal? {
        parsedNewBalance.map { $0 - account.currentBalance.value }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BloomBackground(animated: false).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("系统记录余额")
                                    .font(Theme.Font.caption(.medium))
                                    .foregroundStyle(Theme.Color.textSecondary)
                                AmountText(value: account.currentBalance, currency: account.currency,
                                           font: Theme.Font.cardNumber(), color: Theme.Color.textPrimary)
                            }
                        }
                        field("当前余额") {
                            TextField(plainBalance, text: $newBalanceText)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                                .font(Theme.Font.cardNumber().monospacedDigit())
                        }
                        if let delta {
                            HStack {
                                Text("今日盈亏")
                                    .font(Theme.Font.caption(.medium))
                                    .foregroundStyle(Theme.Color.textSecondary)
                                Spacer(minLength: 8)
                                AmountText(value: DecimalValue(delta), currency: account.currency,
                                           showsPositiveSign: true, font: Theme.Font.subtitle(.semibold),
                                           color: delta < 0 ? Theme.Color.expense : Theme.Color.income)
                            }
                            .padding(12)
                            .glassPanel(cornerRadius: Theme.Radius.button)
                        }
                        field("备注") {
                            TextField("例如：盘后调整", text: $note)
                                .textFieldStyle(.roundedBorder)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Color.expense)
                                .lineLimit(2)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("记当日盈亏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记录") { Task { await submit() } }
                        .disabled(isSubmitting || parsedNewBalance == nil)
                }
            }
        }
    }

    private var plainBalance: String {
        NSDecimalNumber(decimal: account.currentBalance.value).stringValue
    }

    @MainActor
    private func submit() async {
        guard let new = parsedNewBalance else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await model.recordDailyPnL(
                accountID: account.id,
                request: DailyPnLCreateRequest(
                    newBalance: DecimalValue(new),
                    asOfDate: nil,
                    note: trimmedNote.isEmpty ? nil : trimmedNote
                )
            )
            errorMessage = nil
            onRecorded()
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

#endif
