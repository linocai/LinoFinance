import Foundation
import SwiftUI

// ReportsModel — D8 报表 view-model. Loads all 6 reports in parallel; each chart
// binds to its own DTO (plan §D8). Individual report failures degrade to nil so
// one bad endpoint doesn't blank the whole page.
@MainActor
final class ReportsModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

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

    func load() async {
        state = .loading

        // Default the date-windowed reports to the trailing 90 days.
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -90, to: to) ?? to

        async let monthlyResult = try? apiClient.monthlyOverviewReport(dateFrom: from, dateTo: to)
        async let categoryResult = try? apiClient.categoryExpensesReport()
        async let pressureResult = try? apiClient.cashFlowPressureReport(dateFrom: from, dateTo: to)
        async let creditResult = try? apiClient.creditLiabilityTrendReport()
        async let reimResult = try? apiClient.reimbursementReport(view: "all")
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
