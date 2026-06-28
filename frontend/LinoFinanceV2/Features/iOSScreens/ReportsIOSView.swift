import SwiftUI
import Charts

#if os(iOS)

// ReportsIOSView — D8 报表 (iOS · 6 张 Swift Charts, 单列竖排).
//
// Same 6 reports + same real DTO bindings as the macOS ReportsScreen (no fake
// data); only the layout changes — one full-width chart card per row instead of a
// 2-column grid. Each card binds to its own report DTO via the cross-platform
// ReportsModel; individual report failures degrade to 「暂无数据」.

struct ReportsIOSView: View {
    @ObservedObject var model: AppModel
    @StateObject private var reportsModel: ReportsModel

    private let chartHeight: CGFloat = 190

    init(model: AppModel) {
        self.model = model
        _reportsModel = StateObject(wrappedValue: ReportsModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            rangePicker
            switch reportsModel.state {
            case .idle, .loading:
                loadingState
            case .failed(let message):
                failedState(message)
            case .loaded:
                column
            }
        }
        .task {
            if reportsModel.monthly == nil && reportsModel.state == .idle {
                await reportsModel.load()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("报表")
                .font(Theme.Font.pageTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Text("六张图表 · 金额统一折算人民币")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // v2.3.1: 时间范围选择器 (iOS) — drives category / monthly / pressure reports.
    private var rangePicker: some View {
        SegmentedPill(
            options: ReportsModel.DateRange.allCases,
            selection: Binding(
                get: { reportsModel.range },
                set: { newValue in Task { await reportsModel.select(newValue) } }
            )
        ) { $0.title }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 14) {
            monthlyCard
            categoryCard
            pressureCard
            creditCard
            reimbursementCard
            subscriptionCard
        }
    }

    // MARK: - 1. 月度概览

    @ViewBuilder
    private var monthlyCard: some View {
        reportCard("月度概览", subtitle: "收入 / 支出 / 净收入", systemImage: "chart.bar") {
            if let r = reportsModel.monthly {
                let bars: [NamedAmount] = [
                    NamedAmount(label: "收入", value: dbl(r.incomeCny), kind: .income),
                    NamedAmount(label: "支出", value: dbl(r.expenseCny), kind: .expense),
                    NamedAmount(label: "净收入", value: dbl(r.netIncomeCny), kind: .neutral),
                ]
                Chart(bars) { item in
                    BarMark(x: .value("项目", item.label), y: .value("金额", item.value))
                        .foregroundStyle(item.kind.color)
                        .cornerRadius(5)
                }
                .frame(height: chartHeight)
                .chartYAxis { AxisMarks(position: .leading) }
                // v2.3.1: per-bar numbers.
                ReportValueRow(label: "收入", value: r.incomeCny, color: Theme.Color.income)
                ReportValueRow(label: "支出", value: r.expenseCny, color: Theme.Color.expense)
                ReportValueRow(label: "净收入", value: r.netIncomeCny)
                summaryLine("个人净支出", DecimalValue(r.personalNetExpenseCny.value))
            } else {
                noData
            }
        }
    }

    // MARK: - 2. 分类支出

    @ViewBuilder
    private var categoryCard: some View {
        reportCard("分类支出", subtitle: "支出占比靠前的分类", systemImage: "chart.pie") {
            if let r = reportsModel.categoryExpenses, !r.rows.isEmpty {
                let sorted = r.rows.sorted { $0.expenseCny.value > $1.expenseCny.value }
                let top = Array(sorted.prefix(7))
                Chart(top) { row in
                    BarMark(
                        x: .value("金额", dbl(row.expenseCny)),
                        y: .value("分类", row.categoryName)
                    )
                    .foregroundStyle(Theme.Color.brandGradient)
                    .cornerRadius(5)
                }
                .frame(height: chartHeight)
                .chartXAxis { AxisMarks(position: .bottom) }
                // v2.3.1: readable list below the bars — name · amount · share.
                CategoryExpenseList(rows: sorted, totalCny: r.totalExpenseCny)
            } else {
                noData
            }
        }
    }

    // MARK: - 3. 现金流压力

    @ViewBuilder
    private var pressureCard: some View {
        reportCard("现金流压力", subtitle: "未来每日净流入", systemImage: "waveform.path.ecg") {
            if let r = reportsModel.cashFlowPressure, let daily = r.dailyNetCny, !daily.isEmpty {
                Chart(daily) { row in
                    AreaMark(x: .value("日期", row.date), y: .value("净额", dbl(row.netCny)))
                        .foregroundStyle(Theme.Color.link.opacity(0.25))
                    LineMark(x: .value("日期", row.date), y: .value("净额", dbl(row.netCny)))
                        .foregroundStyle(Theme.Color.link)
                }
                .frame(height: chartHeight)
                .chartYAxis { AxisMarks(position: .leading) }
            } else if let r = reportsModel.cashFlowPressure, !r.windows.isEmpty {
                Chart(r.windows) { w in
                    BarMark(x: .value("窗口", "\(w.days)天"), y: .value("净额", dbl(w.netCny)))
                        .foregroundStyle(w.netCny.value < 0 ? Theme.Color.expense : Theme.Color.income)
                        .cornerRadius(5)
                }
                .frame(height: chartHeight)
                .chartYAxis { AxisMarks(position: .leading) }
            } else {
                noData
            }
            // v2.3.1: window numbers (流入/流出/净).
            if let r = reportsModel.cashFlowPressure, !r.windows.isEmpty {
                CashFlowWindowList(windows: r.windows)
            }
        }
    }

    // MARK: - 4. 信用负债趋势

    @ViewBuilder
    private var creditCard: some View {
        reportCard("信用负债趋势", subtitle: "各账单周期剩余负债", systemImage: "creditcard") {
            if let r = reportsModel.creditTrend, !r.rows.isEmpty {
                let rows = r.rows.sorted { $0.statementDate < $1.statementDate }
                Chart(rows) { row in
                    BarMark(
                        x: .value("出账日", row.statementDate, unit: .day),
                        y: .value("剩余", dbl(row.remainingCny))
                    )
                    .foregroundStyle(Theme.Color.expenseStrong)
                    .cornerRadius(4)
                }
                .frame(height: chartHeight)
                .chartYAxis { AxisMarks(position: .leading) }
                // v2.3.1: per-cycle numbers.
                CreditCycleList(rows: rows)
                summaryLine("剩余负债合计", DecimalValue(r.totalRemainingCny.value))
            } else {
                noData
            }
        }
    }

    // MARK: - 5. 报销状态

    @ViewBuilder
    private var reimbursementCard: some View {
        reportCard("报销状态", subtitle: "各状态报销金额", systemImage: "arrow.uturn.left.circle") {
            if let r = reportsModel.reimbursement, !r.statusBreakdown.isEmpty {
                Chart(r.statusBreakdown) { row in
                    BarMark(
                        x: .value("状态", row.status.financeStatusTitle),
                        y: .value("金额", dbl(row.amountCny))
                    )
                    .foregroundStyle(Theme.Color.brandStart)
                    .cornerRadius(5)
                }
                .frame(height: chartHeight)
                .chartYAxis { AxisMarks(position: .leading) }
                // v2.3.1: per-status numbers.
                ForEach(r.statusBreakdown) { row in
                    ReportValueRow(label: row.status.financeStatusTitle, value: row.amountCny)
                }
                summaryLine("个人净支出", DecimalValue(r.personalNetExpenseCny.value))
            } else {
                noData
            }
        }
    }

    // MARK: - 6. 订阅概览

    @ViewBuilder
    private var subscriptionCard: some View {
        reportCard("订阅概览", subtitle: "月度 / 年度 / 未来 30 天", systemImage: "arrow.triangle.2.circlepath") {
            if let r = reportsModel.subscription {
                let bars: [NamedAmount] = [
                    NamedAmount(label: "月度", value: dbl(r.monthlyTotalCny), kind: .neutral),
                    NamedAmount(label: "年度", value: dbl(r.annualTotalCny), kind: .neutral),
                    NamedAmount(label: "未来30天", value: dbl(r.upcoming30DaysCny), kind: .neutral),
                ]
                Chart(bars) { item in
                    BarMark(x: .value("口径", item.label), y: .value("金额", item.value))
                        .foregroundStyle(Theme.Color.brandGradient)
                        .cornerRadius(5)
                }
                .frame(height: chartHeight)
                .chartYAxis { AxisMarks(position: .leading) }
                // v2.3.1: per-bar numbers.
                ReportValueRow(label: "月度", value: r.monthlyTotalCny)
                ReportValueRow(label: "年度", value: r.annualTotalCny)
                ReportValueRow(label: "未来30天", value: r.upcoming30DaysCny)
                summaryLine("启用订阅", count: r.activeSubscriptionCount)
            } else {
                noData
            }
        }
    }

    // MARK: - Shared card chrome

    private func reportCard<Content: View>(
        _ title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.brandEnd)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(Theme.Font.subtitle(.semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text(subtitle)
                            .font(Theme.Font.badge())
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }
                content()
            }
        }
    }

    private func summaryLine(_ label: String, _ value: DecimalValue) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            AmountText(value: value, currency: .cny, font: Theme.Font.caption(.semibold), color: Theme.Color.textPrimary)
        }
    }

    private func summaryLine(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Text("\(count)")
                .font(Theme.Font.caption(.semibold).monospacedDigit())
                .foregroundStyle(Theme.Color.textPrimary)
        }
    }

    private var noData: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("暂无数据")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
        }
        .frame(height: chartHeight)
    }

    // MARK: - States

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载报表…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("报表加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await reportsModel.load() }
                }
            }
        }
    }

    private func dbl(_ value: DecimalValue) -> Double {
        NSDecimalNumber(decimal: value.value).doubleValue
    }
}

// MARK: - Chart row model (iOS-local copy; macOS has its own private one)

private struct NamedAmount: Identifiable {
    enum Kind {
        case income, expense, neutral
        var color: Color {
            switch self {
            case .income: Theme.Color.income
            case .expense: Theme.Color.expense
            case .neutral: Theme.Color.brandEnd
            }
        }
    }
    let id = UUID()
    let label: String
    let value: Double
    let kind: Kind
}

#endif
