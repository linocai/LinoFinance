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
    var attachmentViewModel: AttachmentViewModel
    var creditViewModel: CreditViewModel
    var reportsViewModel: ReportsViewModel
    var aiViewModel: AIWorkspaceViewModel
    var aiMemoViewModel: AIMemoViewModel
    var reconciliationViewModel: ReconciliationViewModel
    var notificationsViewModel: NotificationsViewModel
    var pushNotificationViewModel: PushNotificationViewModel
    var settingsViewModel: SettingsViewModel

    var selectedModule: FinanceModule = .dashboard
    var inspectorSelection: InspectorSelection?
    var isShowingNewAccountSheet = false
    var isShowingNewEntrySheet = false
    var isShowingNewCashFlowSheet = false
    var isShowingEditCashFlowSheet = false
    var editingCashFlowItem: CashFlowItemDTO?
    var isShowingNewReimbursementSheet = false
    var isShowingNewStatementCycleSheet = false
    var isShowingNewInstallmentSheet = false
    var isShowingNewSubscriptionSheet = false
    var isShowingNewNotificationSheet = false
    var isShowingDailyPnLSheet = false
    var dailyPnLTargetAccountID: String?
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
            privacyMaskEnabled ? lockPrivacy() : unlockPrivacy()
        }
    }
    var privacyUnlockMethod: PrivacyUnlockMethod = AppEnvironment.defaultPrivacyUnlockMethod() {
        didSet {
            UserDefaults.standard.set(privacyUnlockMethod.rawValue, forKey: "linofinance.privacyUnlockMethod")
        }
    }
    var privacyAutoMaskOnBackground: Bool = AppEnvironment.defaultBool(
        key: "linofinance.privacyAutoMaskOnBackground",
        defaultValue: true
    ) {
        didSet {
            UserDefaults.standard.set(privacyAutoMaskOnBackground, forKey: "linofinance.privacyAutoMaskOnBackground")
        }
    }
    var privacyIdleLockInterval: PrivacyIdleLockInterval = AppEnvironment.defaultPrivacyIdleLockInterval() {
        didSet {
            UserDefaults.standard.set(privacyIdleLockInterval.rawValue, forKey: "linofinance.privacyIdleLockMinutes")
        }
    }
    var isPrivacyLocked: Bool = false {
        didSet {
            UserDefaults.standard.set(isPrivacyLocked, forKey: "linofinance.privacyLocked")
        }
    }
    var isAuthenticatingPrivacy = false
    private var lastUserInteractionAt = Date()
    var widgetAutoUpdateEnabled: Bool = AppEnvironment.defaultBool(
        key: "linofinance.widgetAutoUpdateEnabled",
        defaultValue: true
    ) {
        didSet {
            UserDefaults.standard.set(widgetAutoUpdateEnabled, forKey: "linofinance.widgetAutoUpdateEnabled")
        }
    }
    var widgetRefreshMinutes: Int = AppEnvironment.defaultInt(
        key: "linofinance.widgetRefreshMinutes",
        defaultValue: 30
    ) {
        didSet {
            UserDefaults.standard.set(widgetRefreshMinutes, forKey: "linofinance.widgetRefreshMinutes")
        }
    }
    var liveActivityReminderDays: Int = AppEnvironment.defaultInt(
        key: "linofinance.liveActivityReminderDays",
        defaultValue: 5
    ) {
        didSet {
            UserDefaults.standard.set(liveActivityReminderDays, forKey: "linofinance.liveActivityReminderDays")
        }
    }
    var dynamicIslandAIEnabled: Bool = AppEnvironment.defaultBool(
        key: "linofinance.dynamicIslandAIEnabled",
        defaultValue: true
    ) {
        didSet {
            UserDefaults.standard.set(dynamicIslandAIEnabled, forKey: "linofinance.dynamicIslandAIEnabled")
        }
    }
    var systemPushEnabled: Bool = AppEnvironment.defaultBool(
        key: "linofinance.systemPushEnabled",
        defaultValue: false
    ) {
        didSet {
            UserDefaults.standard.set(systemPushEnabled, forKey: "linofinance.systemPushEnabled")
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
        self.attachmentViewModel = AttachmentViewModel(apiClient: client)
        self.creditViewModel = CreditViewModel(apiClient: client)
        self.reportsViewModel = ReportsViewModel(apiClient: client)
        self.aiViewModel = AIWorkspaceViewModel(apiClient: client)
        self.aiMemoViewModel = AIMemoViewModel(apiClient: client)
        self.reconciliationViewModel = ReconciliationViewModel(apiClient: client)
        self.notificationsViewModel = NotificationsViewModel(apiClient: client)
        self.pushNotificationViewModel = PushNotificationViewModel(apiClient: client)
        self.settingsViewModel = SettingsViewModel(apiClient: client)
        self.isPrivacyLocked = privacyMaskEnabled
        UserDefaults.standard.set(self.isPrivacyLocked, forKey: "linofinance.privacyLocked")
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
            case .aiMemo:
                try await aiMemoViewModel.refresh()
            case .reconciliation:
                try await reconciliationViewModel.refresh()
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
            try await aiMemoViewModel.refresh()
            try await reconciliationViewModel.refresh()
            try await notificationsViewModel.refresh()
            try await settingsViewModel.refresh()
            WidgetSnapshotStore.shared.writeSnapshot(from: self)
#if canImport(CoreSpotlight)
            await SpotlightIndexer.shared.index(environment: self)
#endif
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
#if canImport(CoreSpotlight)
            if Self.isAuthErrorMessage(error.localizedDescription) {
                await SpotlightIndexer.shared.clear()
            }
#endif
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

    func beginEditCashFlow(_ item: CashFlowItemDTO) {
        editingCashFlowItem = item
        isShowingEditCashFlowSheet = true
    }

    func clearEditCashFlowSheet() {
        isShowingEditCashFlowSheet = false
        editingCashFlowItem = nil
    }

    func beginNewReimbursement() {
        selectedModule = .reimbursements
        isShowingNewReimbursementSheet = true
    }

    func beginAI() {
        selectedModule = .ai
        inspectorSelection = .module(.ai)
    }

    func beginAIMemo() {
        selectedModule = .aiMemo
        inspectorSelection = .module(.aiMemo)
    }

    func beginReconciliation() {
        selectedModule = .reconciliation
        inspectorSelection = .module(.reconciliation)
    }

    func recordUserActivity() {
        lastUserInteractionAt = Date()
    }

    func enforceIdlePrivacyLock() {
        guard privacyMaskEnabled,
              !isPrivacyLocked,
              let seconds = privacyIdleLockInterval.seconds,
              Date().timeIntervalSince(lastUserInteractionAt) >= seconds else {
            return
        }
        lockPrivacy()
    }

    func lockPrivacy() {
        guard privacyMaskEnabled else { return }
        isPrivacyLocked = true
    }

    func unlockPrivacy() {
        isPrivacyLocked = false
        recordUserActivity()
    }

    func lockPrivacyForBackgroundIfNeeded() {
        guard privacyAutoMaskOnBackground else { return }
        lockPrivacy()
    }

    func authenticatePrivacyIfNeeded() async {
        guard privacyMaskEnabled, isPrivacyLocked, !isAuthenticatingPrivacy else {
            return
        }
        if privacyUnlockMethod == .never {
            unlockPrivacy()
            return
        }
        isAuthenticatingPrivacy = true
        defer { isAuthenticatingPrivacy = false }
        do {
            let unlocked = try await PrivacyAuthenticator.shared.authenticate(method: privacyUnlockMethod)
            if unlocked {
                unlockPrivacy()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
        if !isAPITokenConfigured {
#if canImport(CoreSpotlight)
            await SpotlightIndexer.shared.clear()
#endif
        }
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

    @discardableResult
    func recordDailyPnL(
        accountID: String,
        newBalance: Decimal,
        asOfDate: Date? = nil,
        note: String? = nil
    ) async throws -> DailyPnLReadDTO {
        let request = DailyPnLCreateRequest(
            newBalance: DecimalValue(newBalance),
            asOfDate: asOfDate,
            note: note?.isEmpty == false ? note : nil
        )
        return try await apiClient.recordDailyPnL(accountID: accountID, request: request)
    }

    func presentDailyPnLSheet(for accountID: String?) {
        dailyPnLTargetAccountID = accountID
        isShowingDailyPnLSheet = true
    }

    private func rebuildClients(baseURL: URL, apiToken: String?) {
        apiClient = LinoAPIClient(baseURL: baseURL, authToken: apiToken)
        dashboardViewModel = DashboardViewModel(apiClient: apiClient)
        accountsViewModel = AccountsViewModel(apiClient: apiClient)
        entriesViewModel = EntriesViewModel(apiClient: apiClient)
        cashFlowViewModel = CashFlowViewModel(apiClient: apiClient)
        reimbursementsViewModel = ReimbursementsViewModel(apiClient: apiClient)
        attachmentViewModel = AttachmentViewModel(apiClient: apiClient)
        creditViewModel = CreditViewModel(apiClient: apiClient)
        reportsViewModel = ReportsViewModel(apiClient: apiClient)
        aiViewModel = AIWorkspaceViewModel(apiClient: apiClient)
        aiMemoViewModel = AIMemoViewModel(apiClient: apiClient)
        reconciliationViewModel = ReconciliationViewModel(apiClient: apiClient)
        notificationsViewModel = NotificationsViewModel(apiClient: apiClient)
        pushNotificationViewModel = PushNotificationViewModel(apiClient: apiClient)
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

    nonisolated static func defaultPrivacyUnlockMethod() -> PrivacyUnlockMethod {
        guard let value = UserDefaults.standard.string(forKey: "linofinance.privacyUnlockMethod"),
              let method = PrivacyUnlockMethod(rawValue: value) else {
            return .systemAuthentication
        }
        return method
    }

    nonisolated static func defaultPrivacyIdleLockInterval() -> PrivacyIdleLockInterval {
        guard UserDefaults.standard.object(forKey: "linofinance.privacyIdleLockMinutes") != nil,
              let interval = PrivacyIdleLockInterval(rawValue: UserDefaults.standard.integer(forKey: "linofinance.privacyIdleLockMinutes")) else {
            return .fifteen
        }
        return interval
    }

    nonisolated static func defaultBool(key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    nonisolated static func defaultInt(key: String, defaultValue: Int) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.integer(forKey: key)
    }

    nonisolated static func isAuthErrorMessage(_ message: String) -> Bool {
        message.contains("API 401") || message.localizedCaseInsensitiveContains("invalid API token")
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
