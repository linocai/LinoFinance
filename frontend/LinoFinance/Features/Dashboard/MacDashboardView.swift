#if os(macOS)
import SwiftUI

/// macOS 总览页 —— v1.4.0 P3 重构。
/// 自上而下：
///   1. Header（只剩日期，无副标题、无区间切换）
///   2. 四张全宽横幅卡（纵向堆叠，spacing 14）：
///      可支配 / 投资（含今日盈亏快录）/ 净资产（含公式 chips）/ 未来 30 天净流入
///   3. AccountPanoramaCard（账户全景列表）
///
/// 旧的 SegmentedSwitcher 时间段、现金流图表卡、KPICard 四宫格均已移除。
/// 总览页不再拉 reports / ai 的现金流数据（sidebar「现金流」独立页不受影响）。
struct MacDashboardView: View {
    @Bindable var environment: AppEnvironment
    @State private var accountFilter: AccountPanoramaFilter = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let summary = environment.dashboardViewModel.summary {
                    bannerStack(summary: summary)
                    accountPanorama
                } else if environment.dashboardViewModel.isLoading {
                    EmptyState(title: "正在等待总览数据", message: "API 正在计算账户与记录摘要。", systemImage: "network")
                        .padding(.top, 60)
                } else {
                    EmptyState(
                        title: "连接不到 API",
                        message: "请确认后端服务已启动，或检查域名 / API Token 配置。",
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "重试",
                        action: { Task { await environment.refreshPrimaryData() } }
                    )
                    .padding(.top, 60)
                }

                if let message = environment.dashboardViewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .moduleFrame()
        .task {
            await refreshAll()
        }
    }

    // MARK: - Refresh

    @MainActor
    private func refreshAll() async {
        try? await environment.dashboardViewModel.refresh()
        try? await environment.accountsViewModel.refresh()
        try? await environment.settingsViewModel.refresh()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("总览")
                .font(FinanceTypography.titleXL)
                .titleTracking()
                .foregroundStyle(FinanceTokens.Text.primary)
            Text(todayChinese)
                .font(.system(size: 13))
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
    }

    private var todayChinese: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 EEEE"
        return f.string(from: Date())
    }

    // MARK: - Banner stack

    @ViewBuilder
    private func bannerStack(summary: DashboardSummaryDTO) -> some View {
        let investmentAccountCount = environment.accountsViewModel.accounts.investmentAccounts.count

        VStack(spacing: 14) {
            disposableCard(summary)
            investmentCard(summary, accountCount: investmentAccountCount)
            netWorthCard(summary)
            cashFlowCard(summary)
        }
    }

    // 卡1 · 未来一月可支配 —— CNY（绿）/ USD（固定 USD 绿）双币等大异色。
    private func disposableCard(_ summary: DashboardSummaryDTO) -> some View {
        OverviewBannerCard(
            title: "未来一月可支配",
            systemImage: "wallet.bifold",
            tint: FinanceTokens.State.income,
            tag: .init(text: "30 天滚动", style: .draft),
            center: {
                DualCurrencyValue(
                    lines: currencyLines(summary.disposable30dByCurrency),
                    cnyTint: FinanceTokens.State.income
                )
            },
            trailing: { EmptyView() }
        )
    }

    // 卡2 · 投资账户 —— 总额（紫）+ 今日盈亏行；右侧嵌今日盈亏快录表单。
    private func investmentCard(_ summary: DashboardSummaryDTO, accountCount: Int) -> some View {
        OverviewBannerCard(
            title: "投资账户",
            systemImage: "chart.line.uptrend.xyaxis.circle",
            tint: FinanceTokens.State.ai,
            tag: .init(text: "\(accountCount) 账户", style: .draft),
            center: {
                VStack(alignment: .leading, spacing: 8) {
                    DualCurrencyValue(
                        lines: currencyLines(summary.investmentTotalByCurrency),
                        cnyTint: FinanceTokens.State.ai
                    )
                    if let trend = investmentTrendSpec(summary.todayPnlByCurrency) {
                        Text(trend.text)
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(trend.tint)
                    }
                }
            },
            trailing: {
                if accountCount > 0 {
                    DailyPnLQuickForm(environment: environment)
                } else {
                    EmptyView()
                }
            }
        )
    }

    // 卡3 · 净资产 —— CNY/USD 等大 + 每币种一行公式 chips。
    private func netWorthCard(_ summary: DashboardSummaryDTO) -> some View {
        OverviewBannerCard(
            title: "净资产",
            systemImage: "chart.pie",
            tint: FinanceTokens.Brand.primary,
            tag: .init(text: "余额 + 投资 − 信用", style: .draft),
            center: {
                DualCurrencyValue(
                    lines: netWorthLines(summary),
                    cnyTint: FinanceTokens.Brand.primary
                )
            },
            trailing: {
                netWorthFormula(summary)
            }
        )
    }

    // 卡4 · 未来 30 天净流入 —— CNY/USD 等大，数字按正负 income/expense 着色。
    private func cashFlowCard(_ summary: DashboardSummaryDTO) -> some View {
        OverviewBannerCard(
            title: "未来 30 天净流入",
            systemImage: "calendar.badge.clock",
            tint: FinanceTokens.State.credit,
            tag: .init(text: "30 天", style: .draft),
            center: {
                DualCurrencyValue(
                    lines: signedCurrencyLines(summary.cashFlow30dByCurrency),
                    cnyTint: FinanceTokens.State.credit
                )
            },
            trailing: {
                Text("含工资 · 订阅 · 信用卡还款 · 报销到账")
                    .font(FinanceTypography.caption)
                    .foregroundStyle(FinanceTokens.Text.tertiary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
        )
    }

    // MARK: - Value helpers

    /// 把 by-currency 行映射成 DualCurrencyValue 行（默认配色：CNY 走卡 tint，USD 走中性次色）。
    private func currencyLines(_ rows: [CurrencyAmountDTO]?) -> [DualCurrencyValue.CurrencyLine] {
        guard let rows, !rows.isEmpty else { return [] }
        return rows.map { row in
            DualCurrencyValue.CurrencyLine(
                currency: row.currency,
                text: FinanceFormatter.money(row.amount, currency: row.currency)
            )
        }
    }

    /// 卡3 净资产行：优先用 P2 的 `net_worth_by_currency`；后端未部署该字段（旧 prod）时
    /// 回退到标量 `net_worth_cny`，避免卡片空白。
    private func netWorthLines(_ summary: DashboardSummaryDTO) -> [DualCurrencyValue.CurrencyLine] {
        let lines = currencyLines(summary.netWorthByCurrency)
        if !lines.isEmpty { return lines }
        return [DualCurrencyValue.CurrencyLine(
            currency: .cny,
            text: FinanceFormatter.money(summary.netWorthCny, currency: .cny)
        )]
    }

    /// 卡4 专用：数字本身按正负着色（income / expense），覆盖默认双色规则。
    private func signedCurrencyLines(_ rows: [CurrencyAmountDTO]?) -> [DualCurrencyValue.CurrencyLine] {
        guard let rows, !rows.isEmpty else { return [] }
        return rows.map { row in
            let tint: Color
            if row.amount.value > 0 {
                tint = FinanceTokens.State.income
            } else if row.amount.value < 0 {
                tint = FinanceTokens.State.expense
            } else {
                tint = FinanceTokens.Text.secondary
            }
            return DualCurrencyValue.CurrencyLine(
                currency: row.currency,
                text: FinanceFormatter.signedMoney(row.amount, currency: row.currency),
                overrideTint: tint
            )
        }
    }

    /// 今日盈亏 trend 行 —— 沿用 v1.1.6 逻辑：绝对值格式化 + 显式 ASCII 正负号
    /// （避免负号被 locale 当币符砍掉，audit 2.10）。
    private func investmentTrendSpec(_ rows: [CurrencyAmountDTO]?) -> (text: String, tint: Color)? {
        guard let rows, !rows.isEmpty else {
            return ("今日 无数据", FinanceTokens.Text.secondary)
        }
        let segments = rows.map { row -> String in
            let magnitude = row.amount.value < 0 ? row.amount.value * Decimal(-1) : row.amount.value
            let sign: String
            if row.amount.value > 0 {
                sign = "+"
            } else if row.amount.value < 0 {
                sign = "-"
            } else {
                sign = ""
            }
            let body = FinanceFormatter.money(DecimalValue(magnitude), currency: row.currency)
                .dropFirst(row.currency.symbol.count)
            return "\(row.currency.symbol) \(sign)\(body)"
        }
        let totalCny = rows.first(where: { $0.currency == .cny })?.amount.value ?? 0
        let tint: Color
        if totalCny > 0 {
            tint = FinanceTokens.State.income
        } else if totalCny < 0 {
            tint = FinanceTokens.State.expense
        } else {
            tint = FinanceTokens.Text.secondary
        }
        return ("今日 " + segments.joined(separator: " · "), tint)
    }

    // MARK: - Net-worth formula

    /// 按币种各一行公式 chips：`余额 + 投资 − 信用 = 净值`。
    /// 数据完全来自 P2 的四组 by-currency 字段，前端不自行加减（施工总原则 1）。
    /// 迭代 netWorthByCurrency 的币种集合（CNY 恒含，USD 非零才含）。
    private func netWorthFormula(_ summary: DashboardSummaryDTO) -> some View {
        let currencies = (summary.netWorthByCurrency ?? []).map { $0.currency }
        return VStack(alignment: .trailing, spacing: 8) {
            ForEach(currencies, id: \.self) { currency in
                formulaRow(currency: currency, summary: summary)
            }
        }
        .frame(width: 360)
    }

    private func formulaRow(currency: CurrencyCode, summary: DashboardSummaryDTO) -> some View {
        let balance = amount(summary.balanceTotalByCurrency, currency)
        let invest = amount(summary.investmentTotalByCurrency, currency)
        let credit = amount(summary.creditLiabilityByCurrency, currency)
        let net = amount(summary.netWorthByCurrency, currency)
        return HStack(spacing: 6) {
            MetricChip(
                title: "\(currency.rawValue) 余额",
                value: FinanceFormatter.money(balance, currency: currency),
                tint: FinanceTokens.State.income
            )
            operatorGlyph("+")
            MetricChip(
                title: "投资",
                value: FinanceFormatter.money(invest, currency: currency),
                tint: FinanceTokens.State.ai
            )
            operatorGlyph("−")
            MetricChip(
                title: "信用",
                value: FinanceFormatter.money(credit, currency: currency),
                tint: FinanceTokens.State.credit
            )
            operatorGlyph("=")
            MetricChip(
                title: "净值",
                value: FinanceFormatter.money(net, currency: currency),
                tint: FinanceTokens.Brand.primary
            )
        }
    }

    private func operatorGlyph(_ glyph: String) -> some View {
        Text(glyph)
            .font(.system(size: 14, weight: .semibold).monospacedDigit())
            .foregroundStyle(FinanceTokens.Text.tertiary)
    }

    /// 取某币种在某 by-currency 数组中的金额；缺失按 0 处理（仅用于公式展示对齐，
    /// 不参与净值计算——净值直接取后端 netWorthByCurrency）。
    private func amount(_ rows: [CurrencyAmountDTO]?, _ currency: CurrencyCode) -> DecimalValue {
        rows?.first(where: { $0.currency == currency })?.amount ?? DecimalValue(0)
    }

    // MARK: - Account panorama

    private var accountPanorama: some View {
        AccountPanoramaCard(
            title: "账户全景",
            subtitle: "余额账户 + 信用账户 · 含原币 + CNY 折算",
            filter: $accountFilter
        ) {
            VStack(spacing: 0) {
                if filteredAccounts.isEmpty {
                    Text("当前过滤下没有账户")
                        .font(FinanceTypography.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                } else {
                    ForEach(Array(filteredAccounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 {
                            Divider().background(FinanceTokens.Stroke.soft)
                        }
                        accountRow(account)
                            .onTapGesture { environment.inspectorSelection = .account(account) }
                    }
                }
            }
        }
    }

    private var filteredAccounts: [AccountDTO] {
        let all = environment.accountsViewModel.accounts
        switch accountFilter {
        case .all: return all
        case .balance: return all.balanceAccounts
        case .credit: return all.creditAccounts
        }
    }

    private func accountRow(_ account: AccountDTO) -> some View {
        let isCredit = account.type == .credit
        let amount = isCredit ? account.currentLiability : account.currentBalance
        let primary = FinanceFormatter.money(amount, currency: account.currency)
        let convertedCNY = convertedCNY(for: account)
        let secondaryText: String? = {
            guard let convertedCNY else { return nil }
            return FinanceFormatter.money(convertedCNY, currency: .cny, approximate: true)
        }()
        let subtitle: String = {
            if isCredit {
                let s = account.statementDay.map { "账单日 \($0)" } ?? ""
                let d = account.dueDay.map { " · 还款日 \($0)" } ?? ""
                return "信用账户\(s.isEmpty ? "" : " · ")\(s)\(d)"
            } else {
                return "余额账户 · \(account.currency.rawValue)"
            }
        }()
        return AccountListRow(
            systemImage: isCredit ? "creditcard" : iconForBalance(currency: account.currency),
            iconTint: isCredit ? FinanceTokens.State.credit : iconTintForBalance(currency: account.currency),
            title: account.name + " · " + account.currency.rawValue,
            subtitle: subtitle,
            amountPrimary: isCredit ? "-" + primary : primary,
            amountSecondary: secondaryText,
            amountTint: isCredit ? FinanceTokens.State.credit : FinanceTokens.State.income
        )
    }

    private func iconForBalance(currency: CurrencyCode) -> String {
        currency == .usd ? "dollarsign.circle" : "banknote"
    }

    private func iconTintForBalance(currency: CurrencyCode) -> Color {
        currency == .usd ? FinanceTokens.Currency.usd : FinanceTokens.Currency.cny
    }

    private func convertedCNY(for account: AccountDTO) -> DecimalValue? {
        guard account.currency != .cny else { return nil }
        guard let rate = environment.settingsViewModel.rates.first(where: {
            $0.fromCurrency == account.currency && $0.toCurrency == .cny
        }) else {
            return nil
        }
        let amount = account.type == .credit ? account.currentLiability : account.currentBalance
        return DecimalValue(amount.value * rate.rate.value)
    }
}
#endif
