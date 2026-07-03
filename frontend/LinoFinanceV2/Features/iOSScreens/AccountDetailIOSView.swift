import SwiftUI

#if os(iOS)

// AccountDetailIOSView — v2.3.0 P3 单账户流水专屏 · iOS 简版 (D7).
//
// Read-only mirror of the macOS AccountDetailScreen sections (账户头 / 历史流水 /
// 未来现金流 / 信用账单周期 / 分期排期 with REAL settled progress + ALL periods),
// re-flowed to the phone column. No edit / cycle-correction actions here — those
// live on macOS per D7; iOS just lets you see the full account picture incl. the
// previously-hidden multi-period installment schedule.
struct AccountDetailIOSView: View {
    @StateObject private var detail: AccountDetailModel
    let account: AccountDTO
    @Environment(\.dismiss) private var dismiss

    init(apiClient: LinoAPIClient, account: AccountDTO) {
        self.account = account
        _detail = StateObject(wrappedValue: AccountDetailModel(account: account, apiClient: apiClient))
    }

    var body: some View {
        ZStack {
            BloomBackground(animated: false).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleRow
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
                .padding(16)
            }
        }
        .task { await detail.load() }
    }

    private var titleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
                Text(accountSubtitle).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            SubtleTextButton("关闭") { dismiss() }
        }
    }

    private var accountHeaderCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.type == .credit ? "当前欠款" : "当前余额")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                if account.type == .credit {
                    AmountText(value: DecimalValue(-account.currentLiability.value), currency: account.currency,
                               font: Theme.Font.cardNumber(), color: Theme.Color.expense)
                } else {
                    AmountText(value: account.currentBalance, currency: account.currency,
                               font: Theme.Font.cardNumber(),
                               color: account.type == .investment ? Theme.Color.brandEnd : Theme.Color.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private var loadedSections: some View {
        section(title: "历史流水", count: detail.movements.count, emptyHint: "暂无已确认流水。") {
            ForEach(Array(detail.movements.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(Theme.Color.divider) }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(Theme.Font.body(.semibold)).foregroundStyle(Theme.Color.textPrimary).lineLimit(1)
                        Text(FinanceFormatter.shortDate(row.date)).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer(minLength: 8)
                    AmountText(value: row.amount, currency: row.currency,
                               font: Theme.Font.body(.semibold), color: Theme.Color.textSecondary)
                }
                .padding(.vertical, 8)
            }
        }
        section(title: "未来现金流", count: detail.futureCashFlows.count, emptyHint: "暂无未来现金流。") {
            ForEach(Array(detail.futureCashFlows.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Theme.Color.divider) }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(Theme.Font.body(.semibold)).foregroundStyle(Theme.Color.textPrimary).lineLimit(1)
                        Text("\(FinanceFormatter.shortDate(item.expectedDate)) · \(item.statusTitle)")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer(minLength: 8)
                    AmountText(value: item.amount, currency: item.currency,
                               font: Theme.Font.body(.semibold), color: Theme.Color.textSecondary)
                }
                .padding(.vertical, 8)
            }
        }
        if account.type == .credit {
            section(title: "分期排期", count: detail.installments.count, emptyHint: "暂无分期。") {
                ForEach(detail.installments) { progress in
                    installmentBlock(progress)
                }
            }
        }
    }

    private func installmentBlock(_ progress: AccountDetailModel.InstallmentProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("分期 · \(FinanceFormatter.shortDate(progress.plan.startDate))")
                    .font(Theme.Font.body(.semibold)).foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                Text("已还 \(progress.settledCount)/共 \(progress.plan.numberOfPayments) 期")
                    .font(Theme.Font.caption(.medium).monospacedDigit()).foregroundStyle(Theme.Color.textSecondary)
            }
            ForEach(Array(progress.periods.enumerated()), id: \.element.id) { index, period in
                HStack(spacing: 8) {
                    Text("第 \(index + 1) 期").font(Theme.Font.caption(.medium).monospacedDigit())
                        .foregroundStyle(Theme.Color.textTertiary).frame(width: 48, alignment: .leading)
                    Text(FinanceFormatter.shortDate(period.expectedDate)).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                    StatusBadge(text: period.statusTitle, tone: period.statusTone)
                    Spacer(minLength: 8)
                    AmountText(value: period.amount, currency: period.currency,
                               font: Theme.Font.caption(.semibold), color: Theme.Color.textSecondary)
                }
                .padding(.vertical, 5)
            }
        }
        .padding(10)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, count: Int, emptyHint: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(Theme.Font.subtitle(.semibold)).foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Text("\(count)").font(Theme.Font.badge(.semibold).monospacedDigit())
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
            }
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
}

#endif
