import Foundation
import SwiftUI

// AccountsModel — D2 账户 feature view-model (P3).
//
// Owns its own load/error state on top of the shared Core layer
// (`LinoAPIClient`), per the P2 architecture (screens hold their own
// @StateObject view-model; nothing is added to AppModel). Drives the three
// account groups (balance / credit / investment) plus the create / edit /
// daily-pnl mutations.
//
// IRON RULE (HANDOFF §4.2 + plan §D2): `type` / `currency` / `current_balance`
// / `current_liability` are immutable server-side (`extra="forbid"` → 422).
// The edit form disables those four and `AccountUpdateRequest` never carries
// them — balances change ONLY through reconciliation.

@MainActor
final class AccountsModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var accounts: [AccountDTO] = []
    @Published private(set) var rates: [CurrencyRateDTO] = []
    @Published private(set) var state: LoadState = .idle

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Grouping (ordered, all statuses shown; status surfaced per-row)

    var balanceAccounts: [AccountDTO] { grouped(.balance) }
    var creditAccounts: [AccountDTO] { grouped(.credit) }
    var investmentAccounts: [AccountDTO] { grouped(.investment) }

    private func grouped(_ type: AccountType) -> [AccountDTO] {
        accounts.filter { $0.type == type }.sorted(by: AccountDTO.displayOrdered)
    }

    // MARK: - Load

    func load() async {
        if accounts.isEmpty { state = .loading }
        do {
            // Accounts + rates in parallel; rates power the CNY approximation
            // shown under each non-CNY account.
            async let accountsResult = apiClient.listAccounts()
            async let ratesResult = apiClient.listCurrencyRates()
            accounts = try await accountsResult
            rates = (try? await ratesResult) ?? rates
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Mutations (each refreshes the list on success)

    func createAccount(_ request: AccountCreateRequest) async throws {
        _ = try await apiClient.createAccount(request)
        await load()
    }

    /// PATCH the safe editable subset. `type/currency/balance/liability` are NOT
    /// in `AccountUpdateRequest`, so they can never be sent (would 422).
    func updateAccount(_ id: String, request: AccountUpdateRequest) async throws {
        _ = try await apiClient.updateAccount(id, request: request)
        await load()
    }

    /// Record an investment account's current balance for the day; the backend
    /// computes the delta (today's P&L) and adjusts the balance.
    func recordDailyPnL(accountID: String, request: DailyPnLCreateRequest) async throws -> DailyPnLReadDTO {
        let result = try await apiClient.recordDailyPnL(accountID: accountID, request: request)
        await load()
        return result
    }

    // MARK: - CNY approximation (matches v1 AccountsView口径)

    /// Original-currency amount converted to CNY via the latest matching rate,
    /// or nil when the account is already CNY or no rate exists.
    func convertedCNY(for account: AccountDTO) -> DecimalValue? {
        guard account.currency != .cny else { return nil }
        guard let rate = rates.first(where: { $0.fromCurrency == account.currency && $0.toCurrency == .cny }) else {
            return nil
        }
        let amount = account.type == .credit ? account.currentLiability : account.currentBalance
        return DecimalValue(amount.value * rate.rate.value)
    }
}
