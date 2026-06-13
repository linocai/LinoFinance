import Foundation
import SwiftUI

// LedgerModel — D5 流水 feature view-model (P3).
//
// Owns its own load/error state on the shared `LinoAPIClient` (P2 architecture).
// Lists confirmed/voided entries (no draft, v1.4.0 口径), supports the 5 filters
// (全部 / 支出 / 收入 / 转账 / 已作废, with voided hidden by default), top search
// (`GET /search`), and 作废 (软删, 文案=删除). Daily grouping + per-day
// expense/income totals reuse the v1 `EntryTotals` aggregation (CNY 折算, only
// confirmed lines).

@MainActor
final class LedgerModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var entries: [EntryDTO] = []
    @Published private(set) var accounts: [AccountDTO] = []
    @Published private(set) var categories: [CategoryDTO] = []
    @Published private(set) var state: LoadState = .idle
    @Published var actionError: String?

    /// Live server search hits (titles) used to widen the local filter (a search
    /// can match notes / category names the client list doesn't index locally).
    @Published private(set) var searchHitIds: Set<String>?

    private let apiClient: LinoAPIClient
    private var categoryById: [String: CategoryDTO] = [:]

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Load

    func load() async {
        if entries.isEmpty { state = .loading }
        do {
            async let entriesResult = apiClient.listEntries()
            async let accountsResult = apiClient.listAccounts()
            async let categoriesResult = apiClient.listCategories()
            entries = (try await entriesResult).sorted { $0.date > $1.date }
            accounts = (try? await accountsResult) ?? accounts
            let cats = (try? await categoriesResult) ?? categories
            categories = cats
            categoryById = Dictionary(cats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Void (软删 = 删除)

    func voidEntry(_ id: String) async {
        do {
            _ = try await apiClient.voidEntry(id)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Search (GET /search — entries only)

    func runSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchHitIds = nil
            return
        }
        do {
            let response = try await apiClient.search(query: trimmed, limit: 50, types: ["entry"])
            searchHitIds = Set(response.items.map { $0.id })
        } catch {
            // Server search is best-effort; fall back to local title/note match.
            searchHitIds = nil
        }
    }

    // MARK: - Classification

    /// Coarse entry kind for the 支出/收入/转账 filters. Transfers are entries
    /// with no category lines / entry_type "transfer"; otherwise the first
    /// category line's direction decides expense vs income.
    func kind(of entry: EntryDTO) -> LedgerKind {
        if entry.entryType == "transfer" || entry.categoryLines.isEmpty { return .transfer }
        switch entry.categoryLines.first?.direction {
        case .income: return .income
        case .expense: return .expense
        case nil: return .transfer
        }
    }

    func category(_ id: String) -> CategoryDTO? { categoryById[id] }

    func account(_ id: String?) -> AccountDTO? {
        guard let id else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    // MARK: - Per-day totals (CNY 折算, only confirmed — v1 EntryTotals 口径)

    func dailyTotals(_ entries: [EntryDTO]) -> (expense: Decimal, income: Decimal) {
        var expense: Decimal = 0
        var income: Decimal = 0
        for entry in entries where entry.status == .confirmed {
            for line in entry.categoryLines {
                let cny = line.convertedCnyAmount?.value ?? line.amount.value
                guard let cat = categoryById[line.categoryId] else { continue }
                if cat.type == .expense { expense += cny }
                if cat.type == .income { income += cny }
            }
        }
        return (expense, income)
    }
}

enum LedgerKind {
    case expense
    case income
    case transfer
}

/// 流水过滤：全部 / 支出 / 收入 / 转账 / 已作废。默认隐藏 voided（前四项只看
/// 非作废）；「已作废」单列查回收站（v1.4.0 口径，无草稿）。
enum LedgerFilter: String, CaseIterable, Identifiable {
    case all
    case expense
    case income
    case transfer
    case voided

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        case .voided: "已作废"
        }
    }
}
