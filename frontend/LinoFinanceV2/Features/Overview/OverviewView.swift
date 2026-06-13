import SwiftUI

// OverviewView — D1 总览 Dashboard (macOS, glass + dual-currency).
//
// Data: AppModel.dashboard (DashboardSummaryDTO from `GET /dashboard/summary`).
// Layout & figures follow HANDOFF §4.1 + plan §D1 (口径 validated in v1.4.0 —
// this only re-skins the v1 OverviewBannerCard data into liquid glass):
//   • hero (largest GlassCard)  = 未来 30 天可支配  disposable30dByCurrency
//   • net-worth (indigo tint)   = netWorthByCurrency + 公式 chips
//                                 (余额 + 投资 − 信用 = 净资产, CNY 口径)
//   • investment card           = investmentTotalByCurrency + 今日盈亏 todayPnl
//   • 30d net-inflow card       = cashFlow30dByCurrency (signed coloring)
// No chart widget on the right (§4.1). No draft count (draft is废).
//
// Dual-currency arrays are original-currency: CNY is always present, other
// currencies only when non-zero, so a leg is rendered only when it exists.

struct OverviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("总览")
                .font(Theme.Font.pageTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Text("资产与现金流一览 · 双币种原币并排")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // MARK: - Loaded content

    private func content(_ summary: DashboardSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heroCard(summary)
            HStack(alignment: .top, spacing: 16) {
                netWorthCard(summary)
                investmentCard(summary)
                cashFlowCard(summary)
            }
        }
    }

    // hero — 未来 30 天可支配 (largest)
    private func heroCard(_ summary: DashboardSummaryDTO) -> some View {
        GlassCard(padding: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("未来 30 天可支配")
                    .font(Theme.Font.subtitle(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                dualCurrency(summary.disposable30dByCurrency, font: Theme.Font.bigNumber())
                Text("当前余额可动用部分，已扣除未来 30 天的固定支出")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // net worth (indigo tint) + 公式 chips
    private func netWorthCard(_ summary: DashboardSummaryDTO) -> some View {
        GlassCard(tint: Theme.Color.brandEnd) {
            VStack(alignment: .leading, spacing: 10) {
                Text("净资产")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                dualCurrency(summary.netWorthByCurrency, axis: .vertical, font: Theme.Font.cardNumber())

                // 公式 chips (CNY 口径): 余额 + 投资 − 信用 = 净资产
                FlowFormula(
                    balance: cny(summary.balanceTotalByCurrency) ?? summary.balanceTotalCny,
                    investment: cny(summary.investmentTotalByCurrency) ?? (summary.investmentTotalCny ?? DecimalValue(0)),
                    credit: cny(summary.creditLiabilityByCurrency) ?? summary.creditLiabilityTotalCny,
                    net: cny(summary.netWorthByCurrency) ?? summary.netWorthCny
                )
            }
        }
    }

    // investment + 今日盈亏
    private func investmentCard(_ summary: DashboardSummaryDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("投资")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                dualCurrency(summary.investmentTotalByCurrency, axis: .vertical, font: Theme.Font.cardNumber())

                Divider().overlay(Theme.Color.divider)

                Text("今日盈亏")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                signedDualCurrency(summary.todayPnlByCurrency, font: Theme.Font.subtitle(.semibold))
            }
        }
    }

    // 未来 30 天净流入 (signed)
    private func cashFlowCard(_ summary: DashboardSummaryDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("未来 30 天净流入")
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                signedDualCurrency(summary.cashFlow30dByCurrency, axis: .vertical, font: Theme.Font.cardNumber())
                Text("正数为净流入，负数为净流出")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
    }

    // MARK: - Dual-currency rendering

    /// Neutral dual-currency figure (CNY / USD), each leg only if present.
    private func dualCurrency(
        _ legs: [CurrencyAmountDTO]?,
        axis: Axis = .horizontal,
        font: Font
    ) -> some View {
        CurrencyAmountView(
            cny: cny(legs),
            usd: usd(legs),
            axis: axis,
            font: font
        )
    }

    /// Signed (±, green/red) dual-currency figure for P&L / net-inflow.
    @ViewBuilder
    private func signedDualCurrency(
        _ legs: [CurrencyAmountDTO]?,
        axis: Axis = .horizontal,
        font: Font
    ) -> some View {
        let cnyLeg = cny(legs)
        let usdLeg = usd(legs)
        switch axis {
        case .horizontal:
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if let cnyLeg { signedLeg(cnyLeg, currency: .cny, font: font) }
                if cnyLeg != nil && usdLeg != nil { verticalRule }
                if let usdLeg { signedLeg(usdLeg, currency: .usd, font: font) }
                if cnyLeg == nil && usdLeg == nil { emptyDash(font: font) }
            }
        case .vertical:
            VStack(alignment: .leading, spacing: 4) {
                if let cnyLeg { signedLeg(cnyLeg, currency: .cny, font: font) }
                if let usdLeg { signedLeg(usdLeg, currency: .usd, font: font) }
                if cnyLeg == nil && usdLeg == nil { emptyDash(font: font) }
            }
        }
    }

    private func signedLeg(_ value: DecimalValue, currency: CurrencyCode, font: Font) -> some View {
        AmountText(
            value: value,
            currency: currency,
            showsPositiveSign: true,
            font: font,
            color: value.value < 0 ? Theme.Color.expense : Theme.Color.income
        )
    }

    private func emptyDash(font: Font) -> some View {
        Text("—")
            .font(font)
            .foregroundStyle(Theme.Color.textTertiary)
    }

    private var verticalRule: some View {
        Rectangle().fill(Theme.Color.divider).frame(width: 1, height: 18)
    }

    // MARK: - Leg extraction

    private func cny(_ legs: [CurrencyAmountDTO]?) -> DecimalValue? {
        legs?.first(where: { $0.currency == .cny })?.amount
    }

    private func usd(_ legs: [CurrencyAmountDTO]?) -> DecimalValue? {
        legs?.first(where: { $0.currency == .usd })?.amount
    }

    // MARK: - Loading / error states

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
                Button("重试") { Task { await model.loadDashboard() } }
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Net-worth formula chips (余额 + 投资 − 信用 = 净资产, CNY)

private struct FlowFormula: View {
    let balance: DecimalValue
    let investment: DecimalValue
    let credit: DecimalValue
    let net: DecimalValue

    var body: some View {
        // Wrap-friendly flow of small chips with operators between.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                chip("余额", balance)
                op("+")
                chip("投资", investment)
            }
            HStack(spacing: 6) {
                op("−")
                chip("信用", credit)
                op("=")
                chip("净资产", net, emphasized: true)
            }
        }
        .padding(.top, 2)
    }

    private func chip(_ label: String, _ value: DecimalValue, emphasized: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.Font.badge(.semibold))
                .foregroundStyle(Theme.Color.textTertiary)
            AmountText(
                value: value,
                currency: .cny,
                font: Theme.Font.badge(emphasized ? .bold : .semibold),
                color: emphasized ? Theme.Color.brandEnd : Theme.Color.textSecondary
            )
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            (emphasized ? Theme.Color.brandEnd : Theme.Color.textSecondary).opacity(emphasized ? 0.14 : 0.08),
            in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        )
    }

    private func op(_ symbol: String) -> some View {
        Text(symbol)
            .font(Theme.Font.caption(.bold))
            .foregroundStyle(Theme.Color.textTertiary)
    }
}
