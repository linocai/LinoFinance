#if os(macOS)
import AppKit
import Charts
#endif
import SwiftUI

struct ReportsView: View {
    @Bindable var environment: AppEnvironment
    @State private var selectedReport = "monthly"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "分析", subtitle: "报表、洞察与 CSV 导出")

            Picker("报表", selection: $selectedReport) {
                Text("本月总览").tag("monthly")
                Text("分类支出").tag("categories")
                Text("现金流压力").tag("cashflow")
                Text("信用负债").tag("credit")
                Text("报销").tag("reimbursement")
                Text("订阅").tag("subscriptions")
                Text("CSV 导出").tag("exports")
            }
#if os(iOS)
            .pickerStyle(.menu)
#else
            .pickerStyle(.segmented)
#endif

            if let bundle = environment.reportsViewModel.bundle {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedReport {
                        case "categories":
                            CategoryReportPanel(report: bundle.categories)
                        case "cashflow":
                            CashFlowPressurePanel(report: bundle.cashFlow)
                        case "credit":
                            CreditReportPanel(report: bundle.credit)
                        case "reimbursement":
                            ReimbursementReportPanel(report: bundle.reimbursement)
                        case "subscriptions":
                            SubscriptionReportPanel(report: bundle.subscriptions)
                        case "exports":
                            ExportsPanel(environment: environment, exports: bundle.exports)
                        default:
                            MonthlyReportPanel(report: bundle.monthly)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else if environment.reportsViewModel.isLoading {
                EmptyState(title: "正在加载报表", message: "API 正在计算聚合数据。", systemImage: "chart.line.uptrend.xyaxis")
            } else {
                EmptyState(title: "报表尚未加载", message: "点击刷新或检查域名/API Token 配置。", systemImage: "chart.line.uptrend.xyaxis")
            }

            if let message = environment.reportsViewModel.errorMessage {
                ErrorBanner(message: message)
            }
            if let path = environment.reportsViewModel.lastExportPath {
                Label("已导出：\(path)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(FinanceTokens.State.income)
            }
        }
        .padding(FinanceTokens.Spacing.page)
        .moduleFrame()
        .task {
            try? await environment.reportsViewModel.refresh()
        }
    }
}

private func reportGridColumns(minimum: CGFloat = 150) -> [GridItem] {
#if os(iOS)
    [GridItem(.adaptive(minimum: minimum), spacing: 12)]
#else
    Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
#endif
}

private func decimalDouble(_ value: DecimalValue) -> Double {
    NSDecimalNumber(decimal: value.value).doubleValue
}

private struct MonthlyReportPanel: View {
    let report: MonthlyOverviewReportDTO

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ToolbarPill(title: "收入", value: FinanceFormatter.money(report.incomeCny), tint: FinanceTokens.State.income)
            ToolbarPill(title: "支出", value: FinanceFormatter.money(report.expenseCny), tint: FinanceTokens.State.expense)
            ToolbarPill(title: "个人净支出", value: FinanceFormatter.money(report.personalNetExpenseCny), tint: FinanceTokens.Brand.primary)
            ToolbarPill(title: "未来净额", value: FinanceFormatter.money(report.futureNetCny), tint: report.futureNetCny.value < 0 ? FinanceTokens.State.expense : FinanceTokens.State.income)
            ToolbarPill(title: "待报销", value: FinanceFormatter.money(report.expectedReimbursementCny), tint: FinanceTokens.State.ai)
            ToolbarPill(title: "已批准回款", value: FinanceFormatter.money(report.approvedReimbursementCny), tint: FinanceTokens.State.ai)
            ToolbarPill(title: "已到账", value: FinanceFormatter.money(report.receivedReimbursementCny), tint: FinanceTokens.State.income)
            ToolbarPill(title: "信用负债", value: FinanceFormatter.money(report.creditLiabilityCny), tint: FinanceTokens.State.credit)
        }
    }
}

private struct CategoryReportPanel: View {
    let report: CategoryExpenseReportDTO

    private var maxValue: Decimal {
        report.rows.map(\.expenseCny.value).max() ?? 0
    }

    var body: some View {
#if os(macOS)
        MacCategoryChartPanel(report: report)
#else
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("分类支出")
                        .font(.headline)
                    Spacer()
                    MoneyText(amount: report.totalExpenseCny, currency: .cny, prominence: .headline)
                }
                ForEach(report.rows) { row in
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(row.categoryName)
                                .frame(minWidth: 72, idealWidth: 140, maxWidth: 160, alignment: .leading)
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
                    EmptyState(title: "暂无分类支出", message: "创建支出记录后会显示分类分布。", systemImage: "chart.pie")
                }
            }
        }
#endif
    }
}

private struct CashFlowPressurePanel: View {
    let report: CashFlowPressureReportDTO

    var body: some View {
#if os(macOS)
        MacCashFlowPressureChartPanel(report: report)
#else
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            ForEach(report.windows) { window in
                FinancePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("未来 \(window.days) 天")
                            .font(.headline)
                        DetailLine(title: "预计进账", value: FinanceFormatter.money(window.expectedInflowCny))
                        DetailLine(title: "预计出账", value: FinanceFormatter.money(window.expectedOutflowCny))
                        DetailLine(title: "净额", value: FinanceFormatter.money(window.netCny))
                        DetailLine(title: "事件数", value: "\(window.itemCount)")
                    }
                }
            }
        }
#endif
    }
}

private struct CreditReportPanel: View {
    let report: CreditLiabilityTrendReportDTO

    var body: some View {
#if os(macOS)
        MacCreditChartPanel(report: report)
#else
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("信用负债趋势")
                        .font(.headline)
                    Spacer()
                    MoneyText(amount: report.totalRemainingCny, currency: .cny, prominence: .headline)
                }
                ForEach(report.rows) { row in
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            creditTrendSummary(row)
                            Spacer()
                            StatusTag(status: row.status)
                            MoneyText(amount: row.remainingAmount, currency: row.currency)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            creditTrendSummary(row)
                            HStack {
                                StatusTag(status: row.status)
                                Spacer()
                                MoneyText(amount: row.remainingAmount, currency: row.currency)
                            }
                        }
                    }
                    Divider()
                }
                if report.rows.isEmpty {
                    EmptyState(title: "暂无信用账单", message: "创建账单周期后会显示负债趋势。", systemImage: "creditcard")
                }
            }
        }
#endif
    }

    private func creditTrendSummary(_ row: CreditLiabilityTrendRowDTO) -> some View {
        VStack(alignment: .leading) {
            Text(row.accountName)
                .font(.headline)
                .lineLimit(2)
            Text("出账 \(FinanceFormatter.shortDate(row.statementDate)) · 到期 \(FinanceFormatter.shortDate(row.dueDate))")
                .font(.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
                .lineLimit(2)
        }
    }
}

private struct ReimbursementReportPanel: View {
    let report: ReimbursementReportDTO

    var body: some View {
#if os(macOS)
        MacReimbursementChartPanel(report: report)
#else
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: reportGridColumns(), spacing: 12) {
                ToolbarPill(title: "报销前支出", value: FinanceFormatter.money(report.preReimbursementExpenseCny), tint: FinanceTokens.State.expense)
                ToolbarPill(title: "预计抵扣", value: FinanceFormatter.money(report.expectedOffsetCny), tint: FinanceTokens.State.ai)
                ToolbarPill(title: "个人净支出", value: FinanceFormatter.money(report.personalNetExpenseCny), tint: FinanceTokens.Brand.primary)
            }
            FinancePanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("状态拆分")
                        .font(.headline)
                    ForEach(report.statusBreakdown) { row in
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                StatusTag(status: row.status)
                                Text("\(row.claimCount) 笔")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(FinanceTokens.Text.secondary)
                                Spacer()
                                MoneyText(amount: row.amountCny, currency: .cny)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    StatusTag(status: row.status)
                                    Text("\(row.claimCount) 笔")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(FinanceTokens.Text.secondary)
                                }
                                MoneyText(amount: row.amountCny, currency: .cny)
                            }
                        }
                    }
                }
            }
        }
#endif
    }
}

#if os(macOS)
private struct MacCategoryChartPanel: View {
    let report: CategoryExpenseReportDTO

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 16) {
                ReportPanelTitle(title: "分类支出", value: FinanceFormatter.money(report.totalExpenseCny))
                if report.rows.isEmpty {
                    EmptyState(title: "暂无分类支出", message: "创建支出记录后会显示分类分布。", systemImage: "chart.pie")
                } else {
                    Chart(report.rows) { row in
                        SectorMark(
                            angle: .value("支出", decimalDouble(row.expenseCny)),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.4
                        )
                        .cornerRadius(4)
                        .foregroundStyle(by: .value("分类", row.categoryName))
                    }
                    .chartLegend(position: .trailing, alignment: .center)
                    .frame(height: 320)
                }
            }
        }
    }
}

private struct MacCashFlowPressureChartPanel: View {
    let report: CashFlowPressureReportDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FinancePanel {
                VStack(alignment: .leading, spacing: 16) {
                    ReportPanelTitle(title: "现金流压力", value: "未来窗口")
                    Chart {
                        ForEach(report.windows) { window in
                            BarMark(
                                x: .value("窗口", "\(window.days) 天"),
                                y: .value("预计进账", decimalDouble(window.expectedInflowCny))
                            )
                            .foregroundStyle(FinanceTokens.State.income)
                            BarMark(
                                x: .value("窗口", "\(window.days) 天"),
                                y: .value("预计出账", decimalDouble(window.expectedOutflowCny))
                            )
                            .foregroundStyle(FinanceTokens.State.expense)
                            LineMark(
                                x: .value("窗口", "\(window.days) 天"),
                                y: .value("净额", decimalDouble(window.netCny))
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(FinanceTokens.Brand.primary)
                        }
                    }
                    .frame(height: 280)
                }
            }

            FinancePanel {
                VStack(alignment: .leading, spacing: 12) {
                    ReportPanelTitle(title: "30 天日级净额", value: "")
                    let dailyRows = report.dailyNetCny ?? []
                    if dailyRows.isEmpty {
                        EmptyState(title: "暂无日级窗口", message: "后端缺少 daily_net_cny 时会自动降级为空图。", systemImage: "waveform.path.ecg")
                    } else {
                        Chart(dailyRows) { row in
                            BarMark(
                                x: .value("日期", row.date),
                                y: .value("净额", decimalDouble(row.netCny))
                            )
                            .foregroundStyle(decimalDouble(row.netCny) < 0 ? FinanceTokens.State.expense : FinanceTokens.State.income)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 6))
                        }
                        .frame(height: 180)
                    }
                }
            }
        }
    }
}

private struct MacCreditChartPanel: View {
    let report: CreditLiabilityTrendReportDTO

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 16) {
                ReportPanelTitle(title: "信用负债趋势", value: FinanceFormatter.money(report.totalRemainingCny))
                if report.rows.isEmpty {
                    EmptyState(title: "暂无信用账单", message: "创建账单周期后会显示负债趋势。", systemImage: "creditcard")
                } else {
                    Chart {
                        RuleMark(y: .value("零线", 0))
                            .foregroundStyle(FinanceTokens.Stroke.hairline)
                        ForEach(report.rows) { row in
                            BarMark(
                                x: .value("账户", row.accountName),
                                y: .value("剩余负债", decimalDouble(row.remainingCny))
                            )
                            .foregroundStyle(by: .value("状态", row.status.financeStatusTitle))
                            .annotation(position: .top) {
                                Text(FinanceFormatter.money(row.remainingCny))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(FinanceTokens.Text.secondary)
                            }
                        }
                    }
                    .frame(height: 300)
                }
            }
        }
    }
}

private struct MacReimbursementChartPanel: View {
    let report: ReimbursementReportDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: reportGridColumns(), spacing: 12) {
                ToolbarPill(title: "报销前支出", value: FinanceFormatter.money(report.preReimbursementExpenseCny), tint: FinanceTokens.State.expense)
                ToolbarPill(title: "预计抵扣", value: FinanceFormatter.money(report.expectedOffsetCny), tint: FinanceTokens.State.ai)
                ToolbarPill(title: "个人净支出", value: FinanceFormatter.money(report.personalNetExpenseCny), tint: FinanceTokens.Brand.primary)
            }
            FinancePanel {
                VStack(alignment: .leading, spacing: 16) {
                    ReportPanelTitle(title: "报销状态", value: FinanceFormatter.money(report.selectedNetExpenseCny))
                    if report.statusBreakdown.isEmpty {
                        EmptyState(title: "暂无报销数据", message: "标记报销后会显示状态拆分。", systemImage: "arrow.uturn.left.circle")
                    } else {
                        Chart(report.statusBreakdown) { row in
                            BarMark(
                                x: .value("状态", row.status.financeStatusTitle),
                                y: .value("金额", decimalDouble(row.amountCny))
                            )
                            .foregroundStyle(FinanceTokens.State.ai)
                            .annotation(position: .top) {
                                Text("\(row.claimCount) 笔")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(FinanceTokens.Text.secondary)
                            }
                        }
                        .frame(height: 260)
                    }
                }
            }
        }
    }
}

private struct ReportPanelTitle: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(FinanceTypography.headline)
                .foregroundStyle(FinanceTokens.Text.primary)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(FinanceTypography.bodyMono)
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
        }
    }
}
#endif

private struct SubscriptionReportPanel: View {
    let report: SubscriptionReportDTO

    var body: some View {
        LazyVGrid(columns: reportGridColumns(), spacing: 12) {
            ToolbarPill(title: "启用订阅", value: "\(report.activeSubscriptionCount)", tint: FinanceTokens.Brand.primary)
            ToolbarPill(title: "月化总额", value: FinanceFormatter.money(report.monthlyTotalCny), tint: FinanceTokens.State.expense)
            ToolbarPill(title: "未来 30 天", value: FinanceFormatter.money(report.upcoming30DaysCny), tint: FinanceTokens.State.warning)
            ToolbarPill(title: "年化总额", value: FinanceFormatter.money(report.annualTotalCny), tint: FinanceTokens.State.expense)
        }
    }
}

private struct ExportsPanel: View {
    @Bindable var environment: AppEnvironment
    let exports: [ExportDatasetDTO]
    @State private var exportedURL: URL?

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("CSV 数据集")
                    .font(.headline)
                if let exportedURL {
                    ShareLink(item: exportedURL) {
                        Label("分享最近导出的 CSV", systemImage: "square.and.arrow.up")
                    }
                }
                ForEach(exports) { dataset in
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            exportSummary(dataset)
                            Spacer()
                            exportButton(dataset)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            exportSummary(dataset)
                            exportButton(dataset)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func exportSummary(_ dataset: ExportDatasetDTO) -> some View {
        VStack(alignment: .leading) {
            Text(dataset.name)
                .font(.headline)
            Text(dataset.filename)
                .font(.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
                .lineLimit(2)
        }
    }

    private func exportButton(_ dataset: ExportDatasetDTO) -> some View {
        Button {
            Task { await export(dataset) }
        } label: {
            Label("导出", systemImage: "square.and.arrow.down")
        }
    }

    private func export(_ dataset: ExportDatasetDTO) async {
        do {
            let url = try await environment.reportsViewModel.exportCSV(dataset)
            exportedURL = url
#if os(macOS)
            if let path = environment.reportsViewModel.lastExportPath {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
#endif
        } catch {
            environment.lastErrorMessage = error.localizedDescription
        }
    }
}
