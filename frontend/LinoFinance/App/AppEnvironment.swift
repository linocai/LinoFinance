import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let apiClient: LinoAPIClient
    let dashboardViewModel: DashboardViewModel
    let accountsViewModel: AccountsViewModel
    let entriesViewModel: EntriesViewModel
    let cashFlowViewModel: CashFlowViewModel
    let reimbursementsViewModel: ReimbursementsViewModel
    let creditViewModel: CreditViewModel
    let reportsViewModel: ReportsViewModel
    let aiViewModel: AIWorkspaceViewModel
    let notificationsViewModel: NotificationsViewModel
    let settingsViewModel: SettingsViewModel

    var selectedModule: MacModule = .dashboard
    var inspectorSelection: InspectorSelection?
    var isShowingNewAccountSheet = false
    var isShowingNewEntrySheet = false
    var isShowingNewCashFlowSheet = false
    var isShowingNewReimbursementSheet = false
    var isShowingNewStatementCycleSheet = false
    var isShowingNewInstallmentSheet = false
    var isShowingNewSubscriptionSheet = false
    var isShowingNewNotificationSheet = false
    var isSearchFocused = false
    var searchText = ""
    var displayCurrency: CurrencyCode = .cny
    var dateRange: DateRangeChoice = .month
    var lastErrorMessage: String?

    init(
        baseURL: URL = AppEnvironment.defaultAPIBaseURL(),
        apiToken: String? = AppEnvironment.defaultAPIToken()
    ) {
        let apiClient = LinoAPIClient(baseURL: baseURL, authToken: apiToken)
        self.apiClient = apiClient
        self.dashboardViewModel = DashboardViewModel(apiClient: apiClient)
        self.accountsViewModel = AccountsViewModel(apiClient: apiClient)
        self.entriesViewModel = EntriesViewModel(apiClient: apiClient)
        self.cashFlowViewModel = CashFlowViewModel(apiClient: apiClient)
        self.reimbursementsViewModel = ReimbursementsViewModel(apiClient: apiClient)
        self.creditViewModel = CreditViewModel(apiClient: apiClient)
        self.reportsViewModel = ReportsViewModel(apiClient: apiClient)
        self.aiViewModel = AIWorkspaceViewModel(apiClient: apiClient)
        self.notificationsViewModel = NotificationsViewModel(apiClient: apiClient)
        self.settingsViewModel = SettingsViewModel(apiClient: apiClient)
    }

    func refreshCurrentModule() async {
        do {
            switch selectedModule {
            case .dashboard:
                try await dashboardViewModel.refresh()
            case .accounts:
                try await accountsViewModel.refresh()
            case .entries:
                try await entriesViewModel.refresh()
            case .cashFlow:
                try await cashFlowViewModel.refresh()
            case .reimbursements:
                try await reimbursementsViewModel.refresh()
            case .credit:
                try await creditViewModel.refresh()
            case .reports:
                try await reportsViewModel.refresh()
            case .ai:
                try await aiViewModel.refresh()
            case .notifications:
                try await notificationsViewModel.refresh()
            case .settings:
                try await settingsViewModel.refresh()
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshPrimaryData() async {
        do {
            try await dashboardViewModel.refresh()
            try await accountsViewModel.refresh()
            try await entriesViewModel.refresh()
            try await cashFlowViewModel.refresh()
            try await reimbursementsViewModel.refresh()
            try await creditViewModel.refresh()
            try await reportsViewModel.refresh()
            try await aiViewModel.refresh()
            try await notificationsViewModel.refresh()
            try await settingsViewModel.refresh()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func beginNewAccount() {
        selectedModule = .accounts
        isShowingNewAccountSheet = true
    }

    func beginNewEntry() {
        selectedModule = .entries
        isShowingNewEntrySheet = true
    }

    func beginNewCashFlow() {
        selectedModule = .cashFlow
        isShowingNewCashFlowSheet = true
    }

    func beginNewReimbursement() {
        selectedModule = .reimbursements
        isShowingNewReimbursementSheet = true
    }

    func beginAI() {
        selectedModule = .ai
        inspectorSelection = .module(.ai)
    }

    nonisolated static func defaultAPIBaseURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["LINOFINANCE_API_BASE_URL"], let url = URL(string: value) {
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

    nonisolated static func defaultAPIToken() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["LINOFINANCE_API_TOKEN"], !value.isEmpty {
            return value
        }
        if let value = UserDefaults.standard.string(forKey: "linofinance.apiToken"),
           !value.isEmpty {
            return value
        }
        return nil
    }
}

enum DateRangeChoice: String, CaseIterable, Identifiable {
    case week
    case month
    case quarter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "7 天"
        case .month: "本月"
        case .quarter: "90 天"
        }
    }
}
