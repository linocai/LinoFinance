import Foundation
import Observation

@MainActor
@Observable
final class AccountsViewModel {
    private let repository: FinanceRepository
    var accounts: [AccountDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            accounts = try await repository.accounts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func createAccount(_ request: AccountCreateRequest) async throws {
        _ = try await repository.createAccount(request)
        try await refresh()
    }
}
