import SwiftUI

struct DashboardView: View {
    @Bindable var environment: AppEnvironment

    private var pendingAIPlans: [AIPlanDTO] {
        environment.aiViewModel.plans
            .filter { $0.status == "requires_confirmation" || $0.status == "auto_confirm_candidate" }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "总览", subtitle: "API 驱动的财务控制台")

                if let summary = environment.dashboardViewModel.summary {
                    let future30Net = environment.reportsViewModel.bundle?.cashFlow.windows.first { $0.days == 30 }?.netCny
#if os(iOS)
                    HeroDashboardHeader(
                        summary: summary,
                        future30Net: future30Net,
                        dailyNet: environment.reportsViewModel.bundle?.cashFlow.dailyNetCny ?? []
                    )
                    DashboardFocusStrip(
                        todayCount: todayEntryCount,
                        todoCount: pendingAIPlans.count + summary.draftEntryCount,
                        anomalyCount: anomalyCount
                    )
#else
                    SummaryGrid(
                        summary: summary,
                        future30Net: future30Net
                    )
#endif

                    if let bundle = environment.reportsViewModel.bundle {
                        LazyVGrid(columns: dashboardCardColumns, spacing: 16) {
                            DashboardCashFlowCard(report: bundle.cashFlow)
                            DashboardCategoryCard(report: bundle.categories)
                            DashboardReimbursementCard(report: bundle.reimbursement)
                            DashboardAICard(config: environment.aiViewModel.config, plans: pendingAIPlans, draftCount: summary.draftEntryCount)
                        }
                    } else {
                        EmptyState(
                            title: "报表尚未加载",
                            message: "刷新后会显示现金流压力、分类支出和报销视角。",
                            systemImage: "chart.line.uptrend.xyaxis",
                            actionTitle: "刷新",
                            action: { Task { await environment.refreshPrimaryData() } }
                        )
                    }
                } else if environment.dashboardViewModel.isLoading {
                    EmptyState(title: "正在等待总览数据", message: "API 正在计算账户与记录摘要。", systemImage: "network")
                } else {
                    EmptyState(
                        title: "连接不到 API",
                        message: "请确认后端服务已启动，或检查域名/API Token 配置。",
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "重试",
                        action: { Task { await environment.refreshPrimaryData() } }
                    )
                }

                if let message = environment.dashboardViewModel.errorMessage ?? environment.reportsViewModel.errorMessage ?? environment.aiViewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(FinanceTokens.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .moduleFrame()
        .task {
            try? await environment.dashboardViewModel.refresh()
            try? await environment.reportsViewModel.refresh()
            try? await environment.aiViewModel.refresh()
        }
    }

    private var dashboardCardColumns: [GridItem] {
#if os(iOS)
        [GridItem(.adaptive(minimum: 260), spacing: 16)]
#else
        [GridItem(.adaptive(minimum: 300), spacing: 16)]
#endif
    }

    private var todayEntryCount: Int {
        environment.entriesViewModel.entries.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    private var anomalyCount: Int {
        let failedPlans = environment.aiViewModel.plans.filter { $0.status == "failed" }.count
        let overdueCredit = environment.creditViewModel.cycles.filter {
            $0.dueDate < Date() && $0.status != "paid" && $0.status != "closed"
        }.count
        return failedPlans + overdueCredit
    }
}

#if os(iOS)
private struct HeroDashboardHeader: View {
    let summary: DashboardSummaryDTO
    let future30Net: DecimalValue?
    let dailyNet: [CashFlowDailyNetRowDTO]

    private var trendValues: [Double] {
        dailyNet.map { NSDecimalNumber(decimal: $0.netCny.value).doubleValue }
    }

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("净资产")
                            .font(FinanceTypography.caption)
                            .foregroundStyle(FinanceTokens.Text.secondary)
                        HeroNumber(
                            value: FinanceFormatter.money(summary.netWorthCny),
                            tint: FinanceTokens.Brand.primary
                        )
                    }
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(FinanceTokens.Brand.primary)
                }

                Sparkline(values: trendValues, tint: FinanceTokens.Brand.primary)
                    .frame(height: 54)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    MiniMetric(title: "余额", value: FinanceFormatter.money(summary.balanceTotalCny), tint: FinanceTokens.State.income)
                    MiniMetric(title: "信用负债", value: FinanceFormatter.money(summary.creditLiabilityTotalCny), tint: FinanceTokens.State.credit)
                    MiniMetric(title: "30 天净额", value: future30Net.map { FinanceFormatter.money($0) } ?? "暂无", tint: (future30Net?.value ?? 0) < 0 ? FinanceTokens.State.expense : FinanceTokens.State.income)
                }
            }
        }
    }
}

private struct MiniMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(FinanceTokens.Text.secondary)
            PrivacyAmount(
                value: value,
                font: .caption.weight(.semibold).monospacedDigit(),
                tint: tint
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinanceTokens.Surface.glassStrong)
        .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.sm))
    }
}

private struct DashboardFocusStrip: View {
    let todayCount: Int
    let todoCount: Int
    let anomalyCount: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
            FocusTile(title: "今日", value: "\(todayCount)", systemImage: "calendar")
            FocusTile(title: "待办", value: "\(todoCount)", systemImage: "checklist")
            FocusTile(title: "异常", value: "\(anomalyCount)", systemImage: "exclamationmark.triangle")
        }
    }
}

private struct FocusTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(FinanceTokens.Brand.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(FinanceTokens.Text.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.primary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: FinanceTokens.Radius.md)
    }
}
#endif

private struct SummaryGrid: View {
    let summary: DashboardSummaryDTO
    let future30Net: DecimalValue?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            KPIStat(title: "净资产", value: FinanceFormatter.money(summary.netWorthCny), systemImage: "chart.pie.fill", tint: FinanceTokens.Brand.primary)
            KPIStat(title: "余额合计", value: FinanceFormatter.money(summary.balanceTotalCny), systemImage: "wallet.pass.fill", tint: FinanceTokens.State.income)
            KPIStat(title: "信用负债", value: FinanceFormatter.money(summary.creditLiabilityTotalCny), systemImage: "creditcard.trianglebadge.exclamationmark", tint: FinanceTokens.State.credit)
            KPIStat(
                title: future30Net == nil ? "确认记录" : "30 天净额",
                value: future30Net.map { FinanceFormatter.money($0) } ?? "\(summary.confirmedEntryCount)",
                systemImage: future30Net == nil ? "checkmark.seal.fill" : "calendar.badge.clock",
                tint: (future30Net?.value ?? 0) < 0 ? FinanceTokens.State.expense : FinanceTokens.State.income
            )
        }
    }
}

private struct DashboardCashFlowCard: View {
    let report: CashFlowPressureReportDTO

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("未来现金流压力", systemImage: "arrow.left.arrow.right.circle.fill")
                        .font(.headline)
                    Spacer()
                    Text(FinanceFormatter.shortDate(report.anchorDate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(FinanceTokens.Text.secondary)
                }
                ForEach(Array(report.windows.enumerated()), id: \.element.id) { index, window in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("未来 \(window.days) 天")
                            Spacer()
                            MoneyText(amount: window.netCny, currency: .cny, prominence: .headline)
                        }
                        DetailLine(title: "进账 / 出账", value: "\(FinanceFormatter.money(window.expectedInflowCny)) / \(FinanceFormatter.money(window.expectedOutflowCny))")
                    }
                    if index < report.windows.count - 1 {
                        Divider()
                    }
                }
                if report.windows.isEmpty {
                    EmptyState(title: "暂无现金流", message: "创建预计进出账后会显示压力窗口。", systemImage: "calendar.badge.clock")
                }
            }
        }
    }
}

private struct DashboardCategoryCard: View {
    let report: CategoryExpenseReportDTO

    private var maxValue: Decimal {
        report.rows.map(\.expenseCny.value).max() ?? 0
    }

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("分类支出", systemImage: "chart.pie.fill")
                        .font(.headline)
                    Spacer()
                    MoneyText(amount: report.totalExpenseCny, currency: .cny, prominence: .headline)
                }
                ForEach(report.rows.prefix(5)) { row in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top) {
                            Text(row.categoryName)
                                .frame(minWidth: 72, idealWidth: 110, maxWidth: 120, alignment: .leading)
                                .lineLimit(1)
                            ThinBar(value: row.expenseCny, maxValue: maxValue, tint: FinanceTokens.State.expense)
                            MoneyText(amount: row.expenseCny, currency: .cny)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.categoryName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                MoneyText(amount: row.expenseCny, currency: .cny)
                            }
                            ThinBar(value: row.expenseCny, maxValue: maxValue, tint: FinanceTokens.State.expense)
                        }
                    }
                }
                if report.rows.isEmpty {
                    EmptyState(title: "暂无分类支出", message: "确认支出记录后会显示分类分布。", systemImage: "chart.pie")
                }
            }
        }
    }
}

private struct DashboardReimbursementCard: View {
    let report: ReimbursementReportDTO

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("报销视角", systemImage: "arrow.uturn.left.circle.fill")
                    .font(.headline)
                DetailLine(title: "报销前支出", value: FinanceFormatter.money(report.preReimbursementExpenseCny))
                DetailLine(title: "预计抵扣", value: FinanceFormatter.money(report.expectedOffsetCny))
                DetailLine(title: "已批准抵扣", value: FinanceFormatter.money(report.approvedOffsetCny))
                DetailLine(title: "个人净支出", value: FinanceFormatter.money(report.personalNetExpenseCny))
                if !report.statusBreakdown.isEmpty {
                    Divider()
                    ForEach(report.statusBreakdown.prefix(4)) { row in
                        HStack {
                            StatusTag(status: row.status)
                            Text("\(row.claimCount) 笔")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(FinanceTokens.Text.secondary)
                            Spacer()
                            MoneyText(amount: row.amountCny, currency: .cny)
                        }
                    }
                }
            }
        }
    }
}

private struct DashboardAICard: View {
    let config: AIConfigDTO?
    let plans: [AIPlanDTO]
    let draftCount: Int

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI 待确认", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    if let config {
                        StatusTag(title: config.apiKeyConfigured ? "已配置" : "未配置", style: config.apiKeyConfigured ? .confirmed : .warning)
                    }
                }
                DetailLine(title: "草稿记录", value: "\(draftCount)")
                DetailLine(title: "自动确认阈值", value: config.map { FinanceFormatter.money($0.autoConfirmLimitCny) } ?? "未加载")
                Divider()
                if plans.isEmpty {
                    EmptyState(title: "暂无待确认计划", message: "AI 生成的计划会在这里显示摘要和风险级别。", systemImage: "checkmark.seal")
                } else {
                    ForEach(plans) { plan in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.sourceText)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("\(plan.actions.count) 个动作")
                                    .font(.caption)
                                    .foregroundStyle(FinanceTokens.Text.secondary)
                            }
                            Spacer()
                            StatusTag(status: plan.riskLevel)
                        }
                    }
                }
            }
        }
    }
}
