import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let repository: FinanceRepository
    var summary: DashboardSummaryDTO?
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await repository.dashboardSummary()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
