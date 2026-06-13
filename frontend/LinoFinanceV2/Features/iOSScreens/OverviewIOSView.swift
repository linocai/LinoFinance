import SwiftUI

#if os(iOS)

// OverviewIOSView — D1 总览 (iOS · narrow 竖排, liquid glass).
//
// iPhone comp (lf_iphone.png, 左) top→bottom:
//   • hero GlassCard      = 未来 30 天可支配  disposable30dByCurrency
//                            + 现金流净额 small signed line (cashFlow30dByCurrency)
//   • 净资产 card (indigo) = netWorthByCurrency 折合人民币 (CNY 口径大字)
//   • 人民币 / 美元        = two small GlassCards side by side (per-currency balance)
//   • 即将到来 list        = upcoming cash-flow events (CashFlowModel.sortedItems)
//
// Data semantics mirror the macOS OverviewView (same DashboardSummaryDTO fields,
// same dual-currency original-currency口径). Only the layout is re-flowed to the
// narrow phone column. The upcoming list reuses CashFlowModel (cross-platform).

struct OverviewIOSView: View {
    @ObservedObject var model: AppModel
    @StateObject private var cashFlowModel: CashFlowModel

    init(model: AppModel) {
        self.model = model
        _cashFlowModel = StateObject(wrappedValue: CashFlowModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            switch model.dashboardState {
            case .idle, .loading:
                loadingState
            case .failed(let message):
                failedState(message)
            case .loaded:
                if let summary = model.dashboard {
                    content(summary)
                } else {
                    loadingState
                }
            }
        }
        .task { if cashFlowModel.items.isEmpty { await cashFlowModel.load() } }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("总览")
                .font(Theme.Font.pageTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Text("资产与现金流一览")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // MARK: - Loaded content (vertical stack)

    private func content(_ summary: DashboardSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heroCard(summary)
            netWorthCard(summary)
            currencyCards(summary)
            upcomingCard
        }
    }

    // hero — 未来 30 天可支配 (大字) + 现金流净额 small signed line
    private func heroCard(_ summary: DashboardSummaryDTO) -> some View {
        GlassCard(padding: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("未来 30 天可支配")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                CurrencyAmountView(
                    cny: cny(summary.disposable30dByCurrency),
                    usd: usd(summary.disposable30dByCurrency),
                    axis: .vertical,
                    font: Theme.Font.bigNumber()
                )
                HStack(spacing: 6) {
                    Text("现金流净额")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                    signedInline(summary.cashFlow30dByCurrency)
                }
            }
        }
    }

    // net worth (indigo tint) · 折合人民币
    private func netWorthCard(_ summary: DashboardSummaryDTO) -> some View {
        GlassCard(tint: Theme.Color.brandEnd) {
            VStack(alignment: .leading, spacing: 8) {
                Text("净资产 · 折合人民币")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                AmountText(
                    value: cny(summary.netWorthByCurrency) ?? summary.netWorthCny,
                    currency: .cny,
                    font: Theme.Font.cardNumber(.bold),
                    color: Theme.Color.textPrimary
                )
                signedInlineLabeled("现金流净额", summary.cashFlow30dByCurrency)
            }
        }
    }

    // 人民币 / 美元 — two small balance cards side by side (comp 右下并排)
    private func currencyCards(_ summary: DashboardSummaryDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            smallCurrencyCard(
                title: "人民币",
                code: .cny,
                balance: cny(summary.balanceTotalByCurrency) ?? summary.balanceTotalCny,
                pnl: cny(summary.todayPnlByCurrency)
            )
            smallCurrencyCard(
                title: "美元",
                code: .usd,
                balance: usd(summary.balanceTotalByCurrency),
                pnl: usd(summary.todayPnlByCurrency)
            )
        }
    }

    @ViewBuilder
    private func smallCurrencyCard(title: String, code: CurrencyCode, balance: DecimalValue?, pnl: DecimalValue?) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(Theme.Font.caption(.medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text(code.rawValue)
                        .font(Theme.Font.badge(.semibold))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                AmountText(
                    value: balance ?? DecimalValue(0),
                    currency: code,
                    font: Theme.Font.subtitle(.bold),
                    color: code == .cny ? Theme.Color.cny : Theme.Color.usd
                )
                if let pnl {
                    AmountText(
                        value: pnl,
                        currency: code,
                        showsPositiveSign: true,
                        font: Theme.Font.badge(),
                        color: pnl.value < 0 ? Theme.Color.expense : Theme.Color.income
                    )
                } else {
                    Text(" ")
                        .font(Theme.Font.badge())
                }
            }
        }
    }

    // 即将到来 — upcoming cash-flow events (active rows only, soonest first)
    @ViewBuilder
    private var upcomingCard: some View {
        let items = upcomingItems
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("即将到来")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                if items.isEmpty {
                    Text("近期没有预计收支")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().overlay(Theme.Color.divider) }
                            upcomingRow(item)
                                .padding(.vertical, 9)
                        }
                    }
                }
            }
        }
    }

    private func upcomingRow(_ item: CashFlowItemDTO) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.direction == "inflow" ? Theme.Color.income : Theme.Color.expense)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(Self.dateText(item.expectedDate))
                    .font(Theme.Font.badge())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer(minLength: 8)
            AmountText(
                value: signedAmount(item),
                currency: item.currency,
                showsPositiveSign: item.direction == "inflow",
                font: Theme.Font.body(.semibold),
                color: item.direction == "inflow" ? Theme.Color.income : Theme.Color.expense
            )
        }
    }

    private var upcomingItems: [CashFlowItemDTO] {
        cashFlowModel.sortedItems
            .filter { $0.status == "expected" || $0.status == "confirmed" }
            .prefix(5)
            .map { $0 }
    }

    private func signedAmount(_ item: CashFlowItemDTO) -> DecimalValue {
        item.direction == "inflow" ? item.amount : DecimalValue(-item.amount.value)
    }

    // MARK: - Signed inline helpers (现金流净额)

    @ViewBuilder
    private func signedInline(_ legs: [CurrencyAmountDTO]?) -> some View {
        if let value = cny(legs) {
            AmountText(
                value: value,
                currency: .cny,
                showsPositiveSign: true,
                font: Theme.Font.caption(.semibold),
                color: value.value < 0 ? Theme.Color.expense : Theme.Color.income
            )
        } else {
            Text("—")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    @ViewBuilder
    private func signedInlineLabeled(_ label: String, _ legs: [CurrencyAmountDTO]?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textTertiary)
            signedInline(legs)
        }
    }

    // MARK: - Leg extraction (matches macOS OverviewView)

    private func cny(_ legs: [CurrencyAmountDTO]?) -> DecimalValue? {
        legs?.first(where: { $0.currency == .cny })?.amount
    }

    private func usd(_ legs: [CurrencyAmountDTO]?) -> DecimalValue? {
        legs?.first(where: { $0.currency == .usd })?.amount
    }

    // MARK: - States

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载总览…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("总览加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await model.loadDashboard() }
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f
    }()

    private static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }
}

#endif
