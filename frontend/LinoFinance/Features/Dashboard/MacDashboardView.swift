#if os(macOS)
import SwiftUI

/// macOS Dashboard 整页重建 —— 对齐 HTML `v1.1前端升级预览.html` C 节。
/// 自上而下 4 个块：
///   1. Header (h2 "总览" + subtitle + Segmented 时间段)
///   2. KPI 4-col grid (净资产 / 余额合计 / 信用负债 / 未来净额)
///   3. CashflowChartCard (Swift Charts 堆叠柱 + 净额折线)
///   4. AccountPanoramaCard (账户全景列表)
struct MacDashboardView: View {
    @Bindable var environment: AppEnvironment
    @State private var cashflowMode: CashflowChartCard.Mode = .stacked
    @State private var accountFilter: AccountPanoramaFilter = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let summary = environment.dashboardViewModel.summary {
                    kpiGrid(summary: summary)
                    cashflowCard
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

                if let message = environment.dashboardViewModel.errorMessage ?? environment.reportsViewModel.errorMessage ?? environment.aiViewModel.errorMessage {
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
        .onChange(of: environment.dateRange) { _, _ in
            Task { try? await reloadCashflow() }
        }
    }

    // MARK: - Refresh

    @MainActor
    private func refreshAll() async {
        let (from, to) = cashflowRange(for: environment.dateRange)
        try? await environment.dashboardViewModel.refresh()
        try? await environment.reportsViewModel.refresh(cashFlowFrom: from, cashFlowTo: to)
        try? await environment.aiViewModel.refresh()
        try? await environment.accountsViewModel.refresh()
        try? await environment.settingsViewModel.refresh()
    }

    @MainActor
    private func reloadCashflow() async {
        let (from, to) = cashflowRange(for: environment.dateRange)
        try? await environment.reportsViewModel.refresh(cashFlowFrom: from, cashFlowTo: to)
    }

    /// 将 DateRangeChoice 映射成未来 cashflow 起止日期。
    /// week → 今天 ~ 今天+7；month → 今天 ~ 月底；quarter → 今天 ~ 今天+90。
    private func cashflowRange(for choice: DateRangeChoice) -> (Date?, Date?) {
        let now = Date()
        let calendar = Calendar.current
        switch choice {
        case .week:
            let to = calendar.date(byAdding: .day, value: 7, to: now)
            return (now, to)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: now)
            return (now, interval?.end)
        case .quarter:
            let to = calendar.date(byAdding: .day, value: 90, to: now)
            return (now, to)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("总览")
                    .font(FinanceTypography.titleXL)
                    .titleTracking()
                    .foregroundStyle(FinanceTokens.Text.primary)
                Text("API 驱动的财务控制台 · \(todayChinese)")
                    .font(.system(size: 13))
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            Spacer(minLength: 12)
            SegmentedSwitcher(options: DateRangeChoice.allCases, selection: $environment.dateRange) { $0.title }
                .frame(maxWidth: 280)
        }
    }

    private var todayChinese: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 EEEE"
        return f.string(from: Date())
    }

    // MARK: - KPI Grid

    @ViewBuilder
    private func kpiGrid(summary: DashboardSummaryDTO) -> some View {
        let future30Net = environment.reportsViewModel.bundle?.cashFlow.windows.first { $0.days == 30 }?.netCny
        let creditAccountCount = environment.accountsViewModel.accounts.creditAccounts.count
        let balanceAccountCount = environment.accountsViewModel.accounts.balanceAccounts.count
        let nextCredit = nextCreditDueText()

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            KPICard(
                title: "净资产",
                value: FinanceFormatter.money(summary.netWorthCny),
                systemImage: "chart.pie",
                tint: FinanceTokens.Brand.primary,
                tag: .init(text: "CNY 计", style: .draft),
                trend: .init(text: "已确认 \(summary.confirmedEntryCount) · 草稿 \(summary.draftEntryCount)", tint: FinanceTokens.Text.secondary)
            )
            KPICard(
                title: "余额合计",
                value: FinanceFormatter.money(summary.balanceTotalCny),
                systemImage: "wallet.bifold",
                tint: FinanceTokens.State.income,
                tag: .init(text: "\(balanceAccountCount) 账户", style: .income),
                trend: nil
            )
            KPICard(
                title: "信用负债",
                value: FinanceFormatter.money(summary.creditLiabilityTotalCny),
                systemImage: "creditcard",
                tint: FinanceTokens.State.credit,
                tag: .init(text: "\(creditAccountCount) 张", style: .warning),
                trend: nextCredit.map { .init(text: $0, tint: FinanceTokens.State.credit) }
            )
            KPICard(
                title: future30Net == nil ? "确认记录" : "未来 30 天",
                value: future30Net.map { FinanceFormatter.money($0) } ?? "\(summary.confirmedEntryCount)",
                systemImage: future30Net == nil ? "checkmark.seal" : "calendar.badge.clock",
                tint: (future30Net?.value ?? 0) < 0 ? FinanceTokens.State.expense : FinanceTokens.State.income,
                tag: future30Net != nil ? .init(text: "30 天", style: .draft) : nil,
                trend: nil
            )
        }
    }

    private func nextCreditDueText() -> String? {
        let now = Date()
        guard let next = environment.creditViewModel.cycles
            .filter({ $0.status != "paid" && $0.status != "closed" && $0.dueDate >= now })
            .sorted(by: { $0.dueDate < $1.dueDate })
            .first
        else { return nil }
        let days = Calendar.current.dateComponents([.day], from: now, to: next.dueDate).day ?? 0
        let accountName = environment.accountsViewModel.accounts.first(where: { $0.id == next.creditAccountId })?.name ?? "信用卡"
        return "下次 · \(accountName) · \(days) 天"
    }

    // MARK: - Cashflow card

    private var cashflowCard: some View {
        CashflowChartCard(
            buckets: cashflowBuckets,
            mode: $cashflowMode,
            title: "现金流 · \(rangeTitle)",
            subtitle: "含工资 · 订阅 · 信用卡还款 · 报销到账"
        )
    }

    private var rangeTitle: String {
        switch environment.dateRange {
        case .week: "未来 7 天"
        case .month: "本月"
        case .quarter: "未来 90 天"
        }
    }

    /// 把 dailyNetCny 按周分桶。
    /// daily 非空 → 先按当前 dateRange 客户端裁剪（后端如果已经裁过这是 no-op），
    /// 然后按周分桶（最多 12 桶）。
    /// daily 为空且 windows[] 非空时，回落到用 windows 构 3 个桶（7/30/90 天）。
    private var cashflowBuckets: [CashflowChartCard.Bucket] {
        let bundle = environment.reportsViewModel.bundle
        let allDaily = bundle?.cashFlow.dailyNetCny ?? []
        let (from, to) = cashflowRange(for: environment.dateRange)
        let daily = allDaily.filter { row in
            (from.map { row.date >= $0 } ?? true) && (to.map { row.date <= $0 } ?? true)
        }
        guard !daily.isEmpty else {
            return windowsFallback(bundle?.cashFlow.windows ?? [])
        }
        let calendar = Calendar(identifier: .gregorian)
        let sorted = daily.sorted { $0.date < $1.date }
        if sorted.count <= 12 {
            return sorted.map { row in
                CashflowChartCard.Bucket(
                    id: "\(row.date.timeIntervalSince1970)",
                    label: shortMonthDay(row.date),
                    inflow: NSDecimalNumber(decimal: row.inflowCny.value).doubleValue,
                    outflow: NSDecimalNumber(decimal: row.outflowCny.value).doubleValue,
                    net: NSDecimalNumber(decimal: row.netCny.value).doubleValue
                )
            }
        }
        // 7 天一桶
        var grouped: [(weekStart: Date, inflow: Decimal, outflow: Decimal, net: Decimal)] = []
        for row in sorted {
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: row.date)) ?? row.date
            if let lastIdx = grouped.indices.last, grouped[lastIdx].weekStart == weekStart {
                grouped[lastIdx].inflow += row.inflowCny.value
                grouped[lastIdx].outflow += row.outflowCny.value
                grouped[lastIdx].net += row.netCny.value
            } else {
                grouped.append((weekStart, row.inflowCny.value, row.outflowCny.value, row.netCny.value))
            }
        }
        let tail = Array(grouped.suffix(12))
        return tail.map { g in
            CashflowChartCard.Bucket(
                id: "\(g.weekStart.timeIntervalSince1970)",
                label: shortMonthDay(g.weekStart),
                inflow: NSDecimalNumber(decimal: g.inflow).doubleValue,
                outflow: NSDecimalNumber(decimal: g.outflow).doubleValue,
                net: NSDecimalNumber(decimal: g.net).doubleValue
            )
        }
    }

    private func shortMonthDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    /// daily 缺失时的兜底：用 7/30/90 天三个 window 构 3 个桶。
    private func windowsFallback(_ windows: [CashFlowPressureWindowDTO]) -> [CashflowChartCard.Bucket] {
        let sorted = windows.sorted { $0.days < $1.days }
        return sorted.map { w in
            CashflowChartCard.Bucket(
                id: "win-\(w.days)",
                label: "\(w.days) 天",
                inflow: NSDecimalNumber(decimal: w.expectedInflowCny.value).doubleValue,
                outflow: NSDecimalNumber(decimal: w.expectedOutflowCny.value).doubleValue,
                net: NSDecimalNumber(decimal: w.netCny.value).doubleValue
            )
        }
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
            return "约 \(FinanceFormatter.money(convertedCNY, currency: .cny, approximate: true))"
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
