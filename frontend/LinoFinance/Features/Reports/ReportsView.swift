import AppKit
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
            .pickerStyle(.segmented)

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
                EmptyState(title: "正在加载报表", message: "本地 API 正在计算聚合数据。", systemImage: "chart.line.uptrend.xyaxis")
            } else {
                EmptyState(title: "报表尚未加载", message: "点击刷新或确认 6868 本地 API 已启动。", systemImage: "chart.line.uptrend.xyaxis")
            }

            if let message = environment.reportsViewModel.errorMessage {
                ErrorBanner(message: message)
            }
            if let path = environment.reportsViewModel.lastExportPath {
                Label("已导出：\(path)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(FinanceColor.income)
            }
        }
        .padding(24)
        .moduleFrame()
        .task {
            try? await environment.reportsViewModel.refresh()
        }
    }
}

private struct MonthlyReportPanel: View {
    let report: MonthlyOverviewReportDTO

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ToolbarPill(title: "收入", value: FinanceFormatter.money(report.incomeCny), tint: FinanceColor.income)
            ToolbarPill(title: "支出", value: FinanceFormatter.money(report.expenseCny), tint: FinanceColor.expense)
            ToolbarPill(title: "个人净支出", value: FinanceFormatter.money(report.personalNetExpenseCny), tint: FinanceColor.brand)
            ToolbarPill(title: "未来净额", value: FinanceFormatter.money(report.futureNetCny), tint: report.futureNetCny.value < 0 ? FinanceColor.expense : FinanceColor.income)
            ToolbarPill(title: "待报销", value: FinanceFormatter.money(report.expectedReimbursementCny), tint: FinanceColor.ai)
            ToolbarPill(title: "已批准回款", value: FinanceFormatter.money(report.approvedReimbursementCny), tint: FinanceColor.ai)
            ToolbarPill(title: "已到账", value: FinanceFormatter.money(report.receivedReimbursementCny), tint: FinanceColor.income)
            ToolbarPill(title: "信用负债", value: FinanceFormatter.money(report.creditLiabilityCny), tint: FinanceColor.credit)
        }
    }
}

private struct CategoryReportPanel: View {
    let report: CategoryExpenseReportDTO

    private var maxValue: Decimal {
        report.rows.map(\.expenseCny.value).max() ?? 0
    }

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("分类支出")
                        .font(.headline)
                    Spacer()
                    MoneyText(amount: report.totalExpenseCny, currency: .cny, prominence: .headline)
                }
                ForEach(report.rows) { row in
                    HStack {
                        Text(row.categoryName)
                            .frame(width: 160, alignment: .leading)
                        ThinBar(value: row.expenseCny, maxValue: maxValue, tint: FinanceColor.expense)
                        MoneyText(amount: row.expenseCny, currency: .cny)
                    }
                }
                if report.rows.isEmpty {
                    EmptyState(title: "暂无分类支出", message: "创建支出记录后会显示分类分布。", systemImage: "chart.pie")
                }
            }
        }
    }
}

private struct CashFlowPressurePanel: View {
    let report: CashFlowPressureReportDTO

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
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
    }
}

private struct CreditReportPanel: View {
    let report: CreditLiabilityTrendReportDTO

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("信用负债趋势")
                        .font(.headline)
                    Spacer()
                    MoneyText(amount: report.totalRemainingCny, currency: .cny, prominence: .headline)
                }
                ForEach(report.rows) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.accountName)
                                .font(.headline)
                            Text("出账 \(FinanceFormatter.shortDate(row.statementDate)) · 到期 \(FinanceFormatter.shortDate(row.dueDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusTag(status: row.status)
                        MoneyText(amount: row.remainingAmount, currency: row.currency)
                    }
                    Divider()
                }
                if report.rows.isEmpty {
                    EmptyState(title: "暂无信用账单", message: "创建账单周期后会显示负债趋势。", systemImage: "creditcard")
                }
            }
        }
    }
}

private struct ReimbursementReportPanel: View {
    let report: ReimbursementReportDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ToolbarPill(title: "报销前支出", value: FinanceFormatter.money(report.preReimbursementExpenseCny), tint: FinanceColor.expense)
                ToolbarPill(title: "预计抵扣", value: FinanceFormatter.money(report.expectedOffsetCny), tint: FinanceColor.ai)
                ToolbarPill(title: "个人净支出", value: FinanceFormatter.money(report.personalNetExpenseCny), tint: FinanceColor.brand)
            }
            FinancePanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("状态拆分")
                        .font(.headline)
                    ForEach(report.statusBreakdown) { row in
                        HStack {
                            StatusTag(status: row.status)
                            Text("\(row.claimCount) 笔")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            MoneyText(amount: row.amountCny, currency: .cny)
                        }
                    }
                }
            }
        }
    }
}

private struct SubscriptionReportPanel: View {
    let report: SubscriptionReportDTO

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ToolbarPill(title: "启用订阅", value: "\(report.activeSubscriptionCount)", tint: FinanceColor.brand)
            ToolbarPill(title: "月化总额", value: FinanceFormatter.money(report.monthlyTotalCny), tint: FinanceColor.expense)
            ToolbarPill(title: "未来 30 天", value: FinanceFormatter.money(report.upcoming30DaysCny), tint: FinanceColor.warning)
            ToolbarPill(title: "年化总额", value: FinanceFormatter.money(report.annualTotalCny), tint: FinanceColor.expense)
        }
    }
}

private struct ExportsPanel: View {
    @Bindable var environment: AppEnvironment
    let exports: [ExportDatasetDTO]

    var body: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("CSV 数据集")
                    .font(.headline)
                ForEach(exports) { dataset in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(dataset.name)
                                .font(.headline)
                            Text(dataset.filename)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await export(dataset) }
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.down")
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func export(_ dataset: ExportDatasetDTO) async {
        do {
            try await environment.reportsViewModel.exportCSV(dataset)
            if let path = environment.reportsViewModel.lastExportPath {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        } catch {
            environment.lastErrorMessage = error.localizedDescription
        }
    }
}
