import Foundation
import SwiftUI

// AccountDetailModel — v2.3.0 P3 单账户流水专屏 view-model (D5=甲 / D6=甲).
// Cross-platform: macOS 专屏 + iOS 简版只读 both build their detail view on it.
//
// v2.4.0 P3: entries + cash-flow-items are now filtered SERVER-SIDE by
// account_id (was pulled full + filtered client-side). The backend account_id
// filter is status-agnostic (voided entries come back too), so the confirmed /
// non-cancelled filters below are still load-bearing and stay. cycles are still
// server-filtered by credit_account_id; installment plans are still pulled full
// (no account param on that endpoint) and filtered locally. Surfaces, for one
// account:
//   • 历史流水 (account movements drawn from confirmed entries, by movement.accountId)
//   • 未来现金流 (cash flow items by item.accountId, hides cancelled)
//   • 信用账单周期 (cycles, by credit_account_id) — credit accounts only
//   • 分期排期 (each installment plan's per-period 还款 cash flows — ALL N periods,
//      fixing the "只跳到下一期" complaint; backend already generates every period)
@MainActor
final class AccountDetailModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// One row in the historical-movement list (a movement from a confirmed entry).
    struct MovementRow: Identifiable, Hashable {
        let id: String
        let date: Date
        let title: String
        let movementType: MovementType
        let amount: DecimalValue
        let currency: CurrencyCode
    }

    /// One installment plan and the count of its already-settled periods (the
    /// real progress, NOT generatedCashFlowCount which is the total period count).
    struct InstallmentProgress: Identifiable, Hashable {
        let plan: InstallmentPlanDTO
        let settledCount: Int
        /// The per-period 还款 cash flows for this plan (all N periods), date-sorted.
        let periods: [CashFlowItemDTO]
        var id: String { plan.id }
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var movements: [MovementRow] = []
    @Published private(set) var futureCashFlows: [CashFlowItemDTO] = []
    @Published private(set) var statementCycles: [CreditStatementCycleDTO] = []
    @Published private(set) var installments: [InstallmentProgress] = []

    let account: AccountDTO
    private let apiClient: LinoAPIClient

    init(account: AccountDTO, apiClient: LinoAPIClient) {
        self.account = account
        self.apiClient = apiClient
    }

    private var isCredit: Bool { account.type == .credit }

    func load() async {
        state = .loading
        do {
            // entries + cash-flow-items filtered server-side by account_id
            // (v2.4.0 P3); cycles server-filtered by credit_account_id; plans
            // still pulled full (endpoint has no account param) and filtered
            // locally below.
            async let entriesResult = apiClient.listEntries(accountID: account.id)
            async let cashFlowResult = apiClient.listCashFlowItems(accountID: account.id)
            async let cyclesResult = apiClient.listStatementCycles(creditAccountID: account.id)
            async let plansResult = apiClient.listInstallmentPlans()

            let entries = try await entriesResult
            let cashFlows = try await cashFlowResult
            let cycles = (try? await cyclesResult) ?? []
            let plans = (try? await plansResult) ?? []

            // Server returned only entries touching this account, but they are
            // whole entries and status-agnostic — keep the confirmed filter and
            // pick this account's movement(s) out of each entry (movementRows).
            movements = Self.movementRows(from: entries, accountID: account.id)
            // Cash flows already scoped to this account by the server; just hide
            // cancelled and sort by date.
            futureCashFlows = cashFlows
                .filter { $0.status != "cancelled" }
                .sorted { $0.expectedDate < $1.expectedDate }
            statementCycles = isCredit ? cycles : []
            installments = isCredit
                ? Self.installmentProgress(plans: plans, cashFlows: cashFlows, accountID: account.id)
                : []
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Pure transforms

    /// Flatten confirmed entries into per-account movement rows, newest first.
    private static func movementRows(from entries: [EntryDTO], accountID: String) -> [MovementRow] {
        var rows: [MovementRow] = []
        for entry in entries where entry.status == .confirmed {
            for movement in entry.accountMovements where movement.accountId == accountID {
                rows.append(MovementRow(
                    id: movement.id,
                    date: entry.date,
                    title: entry.title,
                    movementType: movement.movementType,
                    amount: movement.amount,
                    currency: movement.currency
                ))
            }
        }
        return rows.sorted { $0.date > $1.date }
    }

    /// Pair each installment plan on this account with its per-period 还款 cash
    /// flows (ALL periods) and the settled count. Settled = the count of this
    /// plan's installment cash flows whose status is "settled" — the *real*
    /// progress, vs `generatedCashFlowCount` (= total periods generated up front).
    private static func installmentProgress(
        plans: [InstallmentPlanDTO],
        cashFlows: [CashFlowItemDTO],
        accountID: String
    ) -> [InstallmentProgress] {
        let installmentFlows = cashFlows.filter { $0.cashFlowType == "installment" }
        return plans
            .filter { $0.creditAccountId == accountID }
            .map { plan in
                let periods = installmentFlows
                    .filter { $0.linkedInstallmentPlanId == plan.id }
                    .sorted { $0.expectedDate < $1.expectedDate }
                let settled = periods.filter { $0.status == "settled" }.count
                return InstallmentProgress(plan: plan, settledCount: settled, periods: periods)
            }
            .sorted { $0.plan.startDate > $1.plan.startDate }
    }
}
