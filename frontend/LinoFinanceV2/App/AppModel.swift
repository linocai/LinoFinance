import Foundation
import SwiftUI

// AppModel — the v2 state layer (P2).
//
// Deliberately NOT the v1 `AppEnvironment` (that lives in the v1 target and pulls
// in v1 views). This is a lean, v2-only model that owns the shared Core layer
// (`LinoAPIClient` + `FinanceRepository`) and caches the handful of resources the
// P2 vertical slice (Overview + Add Entry) needs.
//
// baseURL / token resolution chain is the SAME one v1 + P0 established, so the main
// loop can point the app at the local SQLite runner (6868) the same way:
//   • baseURL  = env LINOFINANCE_API_BASE_URL
//              → UserDefaults "linofinance.apiBaseURL"
//              → Info.plist  LinoFinanceAPIBaseURL
//              → prod https://lf.linotsai.top/api/v1
//   • token    = SecureTokenStore.shared.readEffectiveToken()  (session slot, then admin slot)

@MainActor
final class AppModel: ObservableObject {

    // MARK: - Cached resources

    @Published private(set) var dashboard: DashboardSummaryDTO?
    @Published private(set) var accounts: [AccountDTO] = []
    @Published private(set) var categories: [CategoryDTO] = []
    @Published private(set) var rates: [CurrencyRateDTO] = []

    /// Dashboard load lifecycle, so the Overview can show loading / error states
    /// (never silently blank).
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var dashboardState: LoadState = .idle

    // MARK: - Navigation (hoisted here so menu commands ⌘1–8 / ⌘N can drive it)

    @Published var selection: SidebarDestination = .overview
    @Published var isAddEntryPresented = false

    // MARK: - Networking

    let baseURL: URL
    private let token: String?
    let apiClient: LinoAPIClient
    let repository: FinanceRepository

    init() {
        let resolvedURL = AppModel.resolveBaseURL()
        let resolvedToken = SecureTokenStore.shared.readEffectiveToken()
        self.baseURL = resolvedURL
        self.token = resolvedToken
        self.apiClient = LinoAPIClient(baseURL: resolvedURL, authToken: resolvedToken)
        self.repository = FinanceRepository(apiClient: LinoAPIClient(baseURL: resolvedURL, authToken: resolvedToken))
    }

    var baseURLDescription: String { baseURL.absoluteString }
    var hasToken: Bool { token != nil }

    // MARK: - Loads

    func loadDashboard() async {
        dashboardState = .loading
        do {
            dashboard = try await apiClient.fetchDashboardSummary()
            dashboardState = .loaded
        } catch {
            dashboardState = .failed(error.localizedDescription)
        }
    }

    func loadAccounts() async {
        if let result = try? await apiClient.listAccounts() {
            accounts = result
        }
    }

    func loadCategories() async {
        if let result = try? await apiClient.listCategories() {
            categories = result
        }
    }

    func loadRates() async {
        if let result = try? await apiClient.listCurrencyRates() {
            rates = result
        }
    }

    /// Pull everything the Add Entry form needs (accounts + categories + rates)
    /// plus the dashboard, in parallel.
    func refreshAll() async {
        async let d: Void = loadDashboard()
        async let a: Void = loadAccounts()
        async let c: Void = loadCategories()
        async let r: Void = loadRates()
        _ = await (d, a, c, r)
    }

    // MARK: - Mutations

    /// Create a (confirmed) double-entry record. Throws the underlying API error
    /// so the caller can surface a visible message (never degrades to a draft).
    func submitEntry(_ request: EntryCreateRequest) async throws -> EntryDTO {
        try await repository.createEntry(request)
    }

    /// Latest USD→CNY rate (by date) — used to lock a USD entry's exchange_rate_id
    /// to a concrete row. `nil` when no USD rate exists (the form blocks USD then).
    var latestUSDRate: CurrencyRateDTO? {
        rates
            .filter { $0.fromCurrency == .usd && $0.toCurrency == .cny }
            .max { $0.date < $1.date }
    }

    // MARK: - baseURL resolution (v1 + P0 chain)

    static func resolveBaseURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let value = env["LINOFINANCE_API_BASE_URL"], let url = URL(string: value) {
            return url
        }
        if let value = UserDefaults.standard.string(forKey: "linofinance.apiBaseURL"),
           let url = URL(string: value) {
            return url
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "LinoFinanceAPIBaseURL") as? String,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://lf.linotsai.top/api/v1")!
    }
}

// MARK: - Account grouping helpers (v2-local; v1's live in the v1 target)

extension Array where Element == AccountDTO {
    /// Active balance (cash) accounts, ordered.
    var activeBalanceAccounts: [AccountDTO] {
        filter { $0.type == .balance && $0.status == "active" }
            .sorted(by: AccountDTO.displayOrdered)
    }

    /// Active credit-card accounts, ordered.
    var activeCreditAccounts: [AccountDTO] {
        filter { $0.type == .credit && $0.status == "active" }
            .sorted(by: AccountDTO.displayOrdered)
    }
}

extension AccountDTO {
    static func displayOrdered(_ lhs: AccountDTO, _ rhs: AccountDTO) -> Bool {
        lhs.displayOrder == rhs.displayOrder ? lhs.name < rhs.name : lhs.displayOrder < rhs.displayOrder
    }
}
