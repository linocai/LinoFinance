import Foundation
import Observation

@MainActor
@Observable
final class EntriesViewModel {
    private let repository: FinanceRepository
    var entries: [EntryDTO] = []
    var categories: [CategoryDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    var expenseCategories: [CategoryDTO] {
        categories
            .filter { $0.type == .expense && $0.isActive }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedCategories = try await repository.categories()
            let loadedEntries = try await repository.entries()
            categories = loadedCategories
            entries = loadedEntries.sorted { $0.date > $1.date }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func createCategory(_ request: CategoryCreateRequest) async throws {
        _ = try await repository.createCategory(request)
        categories = try await repository.categories()
    }

    func createEntry(_ request: EntryCreateRequest) async throws {
        _ = try await repository.createEntry(request)
        try await refresh()
    }

    func voidEntry(_ id: String) async throws {
        _ = try await repository.voidEntry(id)
        try await refresh()
    }
}
