import Foundation
import SwiftUI

#if os(macOS)

// ReconciliationModel — D9 对账 view-model.
//
// Owns the reconciliation snapshot (`GET /reconciliation/accounts`) and submits
// adjustments (`POST /reconciliation/adjustments`). Account balances change ONLY
// through here (plan §D9), so this is the single mutation path for a balance.
//
// `AccountAdjustmentCreateRequest.actualAmount` is the user's *actual* observed
// balance; the backend computes the delta against the system-of-record balance,
// so the screen does NOT send a delta — it sends the target actual amount.
@MainActor
final class ReconciliationModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var snapshot: ReconciliationAccountsResponseDTO?
    @Published private(set) var state: LoadState = .idle

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    var rows: [ReconciliationAccountDTO] { snapshot?.items ?? [] }

    func load() async {
        state = .loading
        do {
            snapshot = try await apiClient.listReconciliationAccounts()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Generate a balance adjustment for `accountId` so its system balance matches
    /// the user-observed `actualAmount`. Reloads the snapshot on success so the
    /// delta column zeroes out. Throws so the caller can surface a visible error.
    @discardableResult
    func submitAdjustment(
        accountId: String,
        actualAmount: DecimalValue,
        reason: String,
        note: String?
    ) async throws -> AccountAdjustmentDTO {
        let request = AccountAdjustmentCreateRequest(
            accountId: accountId,
            actualAmount: actualAmount,
            reason: reason,
            note: note
        )
        let result = try await apiClient.createAccountAdjustment(request)
        await load()
        return result
    }
}

#endif
