import Observation
import SwiftUI

@MainActor
@Observable
final class AppEnvironment {
    var apiClient: LinoAPIClient
    var dashboardViewModel: DashboardViewModel
    var accountsViewModel: AccountsViewModel
    var entriesViewModel: EntriesViewModel
    var cashFlowViewModel: CashFlowViewModel
    var reimbursementsViewModel: ReimbursementsViewModel
    var creditViewModel: CreditViewModel
    var reportsViewModel: ReportsViewModel
    var aiViewModel: AIWorkspaceViewModel
    var notificationsViewModel: NotificationsViewModel
    var settingsViewModel: SettingsViewModel

    var selectedModule: FinanceModule = .dashboard
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
    var appearance: FinanceAppearance = AppEnvironment.defaultAppearance() {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "linofinance.appearance")
        }
    }
    var useHeroNumbers: Bool = AppEnvironment.defaultBool(
        key: "linofinance.useHeroNumbers",
        defaultValue: true
    ) {
        didSet {
            UserDefaults.standard.set(useHeroNumbers, forKey: "linofinance.useHeroNumbers")
        }
    }
    var privacyMaskEnabled: Bool = AppEnvironment.defaultBool(
        key: "linofinance.privacyMaskEnabled",
        defaultValue: false
    ) {
        didSet {
            UserDefaults.standard.set(privacyMaskEnabled, forKey: "linofinance.privacyMaskEnabled")
        }
    }
    var isAPITokenConfigured: Bool { apiClient.authToken != nil }

    init(
        baseURL: URL = AppEnvironment.defaultAPIBaseURL(),
        apiToken: String? = AppEnvironment.defaultAPIToken()
    ) {
        let client = LinoAPIClient(baseURL: baseURL, authToken: apiToken)
        self.apiClient = client
        self.dashboardViewModel = DashboardViewModel(apiClient: client)
        self.accountsViewModel = AccountsViewModel(apiClient: client)
        self.entriesViewModel = EntriesViewModel(apiClient: client)
        self.cashFlowViewModel = CashFlowViewModel(apiClient: client)
        self.reimbursementsViewModel = ReimbursementsViewModel(apiClient: client)
        self.creditViewModel = CreditViewModel(apiClient: client)
        self.reportsViewModel = ReportsViewModel(apiClient: client)
        self.aiViewModel = AIWorkspaceViewModel(apiClient: client)
        self.notificationsViewModel = NotificationsViewModel(apiClient: client)
        self.settingsViewModel = SettingsViewModel(apiClient: client)
#if os(iOS)
        if apiToken == nil {
            selectedModule = .settings
        }
#endif
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

    func configureAPI(baseURL: URL, apiToken: String?) async {
        UserDefaults.standard.set(baseURL.absoluteString, forKey: "linofinance.apiBaseURL")
        do {
            try SecureTokenStore.shared.saveToken(apiToken)
            UserDefaults.standard.removeObject(forKey: "linofinance.apiToken")
        } catch {
            lastErrorMessage = error.localizedDescription
            return
        }
        rebuildClients(baseURL: baseURL, apiToken: apiToken)
        do {
            try await settingsViewModel.refresh()
            if isAPITokenConfigured {
                await refreshPrimaryData()
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func rebuildClients(baseURL: URL, apiToken: String?) {
        apiClient = LinoAPIClient(baseURL: baseURL, authToken: apiToken)
        dashboardViewModel = DashboardViewModel(apiClient: apiClient)
        accountsViewModel = AccountsViewModel(apiClient: apiClient)
        entriesViewModel = EntriesViewModel(apiClient: apiClient)
        cashFlowViewModel = CashFlowViewModel(apiClient: apiClient)
        reimbursementsViewModel = ReimbursementsViewModel(apiClient: apiClient)
        creditViewModel = CreditViewModel(apiClient: apiClient)
        reportsViewModel = ReportsViewModel(apiClient: apiClient)
        aiViewModel = AIWorkspaceViewModel(apiClient: apiClient)
        notificationsViewModel = NotificationsViewModel(apiClient: apiClient)
        settingsViewModel = SettingsViewModel(apiClient: apiClient)
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
        if let value = SecureTokenStore.shared.readToken(), !value.isEmpty {
            return value
        }
        if let value = UserDefaults.standard.string(forKey: "linofinance.apiToken"),
           !value.isEmpty {
            return value
        }
        return nil
    }

    nonisolated static func defaultAppearance() -> FinanceAppearance {
        guard let value = UserDefaults.standard.string(forKey: "linofinance.appearance"),
              let appearance = FinanceAppearance(rawValue: value) else {
            return .system
        }
        return appearance
    }

    nonisolated static func defaultBool(key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
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

enum FinanceAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
