import Foundation
import SwiftUI

// ReportsModel — D8 报表 view-model. Loads all 6 reports in parallel; each chart
// binds to its own DTO (plan §D8). Individual report failures degrade to nil so
// one bad endpoint doesn't blank the whole page.
//
// v2.3.1 报表数字化: a `DateRange` window selector (近7天/近30天/近90天/本月,
// default 近30天) drives the date-windowed reports (category-expenses +
// monthly-overview + cash-flow-pressure). Changing the window refetches. The
// non-windowed reports (credit-trend / reimbursement / subscription) are
// window-independent and reload unchanged.
@MainActor
final class ReportsModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // v2.3.1: window selector for the date-windowed reports. Default 近30天.
    enum DateRange: String, CaseIterable, Identifiable {
        case last7, last30, last90, thisMonth
        var id: String { rawValue }
        var title: String {
            switch self {
            case .last7: "近7天"
            case .last30: "近30天"
            case .last90: "近90天"
            case .thisMonth: "本月"
            }
        }

        /// (from, to) for this window. `近N天` = today-N → today; `本月` = 当月1号 → today.
        func bounds(now: Date = Date(), calendar: Calendar = .current) -> (from: Date, to: Date) {
            let to = now
            switch self {
            case .last7:
                return (calendar.date(byAdding: .day, value: -7, to: to) ?? to, to)
            case .last30:
                return (calendar.date(byAdding: .day, value: -30, to: to) ?? to, to)
            case .last90:
                return (calendar.date(byAdding: .day, value: -90, to: to) ?? to, to)
            case .thisMonth:
                let comps = calendar.dateComponents([.year, .month], from: to)
                let monthStart = calendar.date(from: comps) ?? to
                return (monthStart, to)
            }
        }
    }

    @Published var range: DateRange = .last30

    @Published private(set) var monthly: MonthlyOverviewReportDTO?
    @Published private(set) var categoryExpenses: CategoryExpenseReportDTO?
    @Published private(set) var cashFlowPressure: CashFlowPressureReportDTO?
    @Published private(set) var creditTrend: CreditLiabilityTrendReportDTO?
    @Published private(set) var reimbursement: ReimbursementReportDTO?
    @Published private(set) var subscription: SubscriptionReportDTO?
    @Published private(set) var state: LoadState = .idle

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    /// Switch the date window and refetch. No-op if the window is unchanged.
    func select(_ newRange: DateRange) async {
        guard newRange != range else { return }
        range = newRange
        await load()
    }

    func load() async {
        state = .loading

        // Date-windowed reports follow the selected window (default 近30天).
        let bounds = range.bounds()
        let from = bounds.from
        let to = bounds.to

        async let monthlyResult = try? apiClient.monthlyOverviewReport(dateFrom: from, dateTo: to)
        async let categoryResult = try? apiClient.categoryExpensesReport(dateFrom: from, dateTo: to)
        async let pressureResult = try? apiClient.cashFlowPressureReport(dateFrom: from, dateTo: to)
        async let creditResult = try? apiClient.creditLiabilityTrendReport()
        // v2.1.0 P2: the "all" view was removed; reports only reads the
        // view-independent statusBreakdown, so any valid view works.
        async let reimResult = try? apiClient.reimbursementReport(view: "personal_net")
        async let subResult = try? apiClient.subscriptionReport()

        monthly = await monthlyResult
        categoryExpenses = await categoryResult
        cashFlowPressure = await pressureResult
        creditTrend = await creditResult
        reimbursement = await reimResult
        subscription = await subResult

        // If literally every report failed, surface the error state so the user
        // gets a retry instead of six empty cards (almost always an auth/network
        // problem, not six independent empties).
        if monthly == nil && categoryExpenses == nil && cashFlowPressure == nil
            && creditTrend == nil && reimbursement == nil && subscription == nil {
            state = .failed("报表数据加载失败，请检查网络或登录状态后重试。")
        } else {
            state = .loaded
        }
    }
}

// MARK: - v2.3.1 报表数字化 · shared readable lists (cross-platform)

/// A single label → CNY amount row (R0: `Text` + `AmountText`, no native list).
struct ReportValueRow: View {
    let label: String
    let value: DecimalValue
    var color: Color = Theme.Color.textPrimary
    var dotColor: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            AmountText(value: value, currency: .cny, font: Theme.Font.caption(.semibold), color: color)
        }
    }
}

/// 分类支出 readable list: `● 分类 …… ¥金额 (占比%)`, descending, + 合计 footer.
/// Non-CNY original-currency amounts are shown as a small sub-line per row.
struct CategoryExpenseList: View {
    let rows: [CategoryExpenseRowDTO]
    let totalCny: DecimalValue

    private static let dotPalette: [Color] = [
        Theme.Color.brandStart, Theme.Color.brandEnd, Theme.Color.link,
        Theme.Color.income, Theme.Color.expense, Theme.Color.expenseStrong,
    ]

    private func share(_ value: DecimalValue) -> String {
        let total = NSDecimalNumber(decimal: totalCny.value).doubleValue
        guard total > 0 else { return "—" }
        let pct = NSDecimalNumber(decimal: value.value).doubleValue / total * 100
        return String(format: "%.1f%%", pct)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Self.dotPalette[index % Self.dotPalette.count])
                            .frame(width: 7, height: 7)
                        Text(row.categoryName)
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        AmountText(
                            value: row.expenseCny, currency: .cny,
                            font: Theme.Font.caption(.semibold), color: Theme.Color.textPrimary
                        )
                        Text("(\(share(row.expenseCny)))")
                            .font(Theme.Font.badge().monospacedDigit())
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    // Original currencies (non-CNY) sub-line, e.g. 「$12.00 ≈ ¥81.60」.
                    let foreign = row.currencies.filter { $0.currency != .cny }
                    if !foreign.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(foreign, id: \.currency) { c in
                                Text(originalLine(c))
                                    .font(Theme.Font.badge())
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                        }
                        .padding(.leading, 15)
                    }
                }
            }
            Divider().opacity(0.5)
            HStack {
                Text("合计")
                    .font(Theme.Font.caption(.semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                AmountText(
                    value: totalCny, currency: .cny,
                    font: Theme.Font.caption(.semibold), color: Theme.Color.textPrimary
                )
            }
        }
    }

    private func originalLine(_ c: CurrencyAmountSummaryDTO) -> String {
        let amt = AmountText.plainString(value: c.amount, currency: c.currency)
        let cny = AmountText.plainString(value: c.convertedCnyAmount, currency: .cny)
        return "\(amt) ≈ \(cny)"
    }
}

/// 现金流压力 readable list: per 7/30/90 天 window — 流入 / 流出 / 净.
struct CashFlowWindowList: View {
    let windows: [CashFlowPressureWindowDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(windows) { w in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("未来 \(w.days) 天")
                            .font(Theme.Font.caption(.semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Spacer()
                        AmountText(
                            value: w.netCny, currency: .cny, showsPositiveSign: true,
                            font: Theme.Font.caption(.semibold),
                            color: w.netCny.value < 0 ? Theme.Color.expense : Theme.Color.income
                        )
                    }
                    HStack(spacing: 14) {
                        labeled("流入", w.expectedInflowCny, Theme.Color.income)
                        labeled("流出", w.expectedOutflowCny, Theme.Color.expense)
                        Spacer()
                    }
                    .padding(.leading, 2)
                }
            }
        }
    }

    private func labeled(_ label: String, _ value: DecimalValue, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.Font.badge())
                .foregroundStyle(Theme.Color.textTertiary)
            AmountText(value: value, currency: .cny, font: Theme.Font.badge(), color: color)
        }
    }
}

/// 信用负债 readable list: per cycle — 账户名 · 账单额 / 剩余.
struct CreditCycleList: View {
    let rows: [CreditLiabilityTrendRowDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.accountName)
                            .font(Theme.Font.caption(.semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        AmountText(
                            value: row.remainingCny, currency: .cny,
                            font: Theme.Font.caption(.semibold), color: Theme.Color.expenseStrong
                        )
                    }
                    HStack(spacing: 6) {
                        Text("账单 \(AmountText.plainString(value: row.statementAmount, currency: row.currency))")
                        Text("·")
                        Text("已还 \(AmountText.plainString(value: row.paidAmount, currency: row.currency))")
                    }
                    .font(Theme.Font.badge())
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.leading, 2)
                }
            }
        }
    }
}
