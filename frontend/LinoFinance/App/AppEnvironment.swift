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
    var isShowingSettleCashFlowSheet = false
    var settlingCashFlowItem: CashFlowItemDTO?
    var isShowingNewReimbursementSheet = false
    var isShowingNewStatementCycleSheet = false
    var isShowingNewInstallmentSheet = false
    var isShowingNewSubscriptionSheet = false
    var isShowingNewNotificationSheet = false
    var isShowingDailyPnLSheet = false
    var dailyPnLTargetAccountID: String?
    var isSearchFocused = false
    var searchText = ""
#if DEBUG
    // DEBUG-only DesignSystem Showcase 触发位（v1.4.0 P4：从 MacRootView 本地
    // @State 提升到 environment，让 LinoFinanceApp 的 #if DEBUG CommandMenu 可唤起）。
    var isShowingDesignShowcase = false
#endif
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

    // MARK: - Auth (Sign in with Apple, v1.2)

    /// The Apple-signed-in user, or nil when signed out or using the admin token.
    var authUser: AuthUserDTO?
    /// True when the effective token is the env admin token (no Apple identity).
    var isAdminSession = false
    /// Active sessions for the current user, for the Settings → 已登录设备 list.
    var activeSessions: [AuthSessionDTO] = []
    /// True while `loadCurrentUser()` is in flight (used by the launch splash).
    var isResolvingAuth = false
    /// The session id the current device authenticated with, for the "本机" badge.
    var currentSessionID: String?

    /// True when neither an Apple session nor an admin token is configured —
    /// the client should show the Sign in with Apple screen.
    var needsSignIn: Bool {
        authUser == nil && !isAdminSession && !isAPITokenConfigured
    }

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
            if Self.isUnauthorized(error) {
                handleUnauthorized()
#if canImport(CoreSpotlight)
                await SpotlightIndexer.shared.clear()
#endif
            } else {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// Centralized 401 recovery (audit 2.12). Distinguishes the two keychain
    /// slots so a stale token no longer forces the user to kill and relaunch
    /// the app:
    /// - **Session slot** (an Apple session token is present): clear the session
    ///   token, drop the cached user, and rebuild clients on the remaining
    ///   effective token. With no session and no admin token, `needsSignIn`
    ///   flips true and the Sign in with Apple screen takes over.
    /// - **Admin slot** (manual admin token, no session token): keep the token
    ///   — only surface a banner. The admin/ops bypass token is long-lived and
    ///   a transient 401 must not silently wipe it.
    private func handleUnauthorized() {
        let hasSessionToken = SecureTokenStore.shared.readToken(kind: .session) != nil
        if hasSessionToken {
            try? SecureTokenStore.shared.clear(kind: .session)
            authUser = nil
            isAdminSession = false
            currentSessionID = nil
            activeSessions = []
            rebuildClients(
                baseURL: apiClient.baseURL,
                apiToken: SecureTokenStore.shared.readEffectiveToken()
            )
            lastErrorMessage = nil
        } else {
            // Admin-token mode: keep the token, just inform the user.
            lastErrorMessage = "管理员 Token 鉴权失败（401）。请在设置中检查 Token 是否仍然有效。"
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

    func beginSettleCashFlow(_ item: CashFlowItemDTO) {
        settlingCashFlowItem = item
        isShowingSettleCashFlowSheet = true
    }

    func clearSettleCashFlowSheet() {
        isShowingSettleCashFlowSheet = false
        settlingCashFlowItem = nil
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
            // Manual token entry in v1.2 is the admin escape hatch.
            try SecureTokenStore.shared.saveToken(apiToken, kind: .admin)
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

    /// Change the API base URL without touching the stored tokens. Rebuilds
    /// the clients around the existing effective token and re-resolves auth.
    func updateBaseURL(_ baseURL: URL) async {
        UserDefaults.standard.set(baseURL.absoluteString, forKey: "linofinance.apiBaseURL")
        rebuildClients(baseURL: baseURL, apiToken: SecureTokenStore.shared.readEffectiveToken())
        await loadCurrentUser()
        if !needsSignIn {
            await refreshSessions()
            await refreshPrimaryData()
        }
    }

    // MARK: - Auth flow

    static var currentPlatform: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Exchange an Apple identity_token for a session token, persist it, and
    /// reconfigure the API client around it.
    func signInWithApple(
        identityToken: String,
        firstName: String?,
        lastName: String?,
        deviceLabel: String
    ) async throws {
        let request = AppleSignInRequest(
            identityToken: identityToken,
            deviceLabel: deviceLabel,
            platform: Self.currentPlatform,
            appVersion: Self.currentAppVersion,
            firstName: firstName,
            lastName: lastName
        )
        let response = try await apiClient.signInWithApple(request)
        try SecureTokenStore.shared.saveToken(response.sessionToken, kind: .session)
        rebuildClients(baseURL: apiClient.baseURL, apiToken: response.sessionToken)
        authUser = response.user
        isAdminSession = false
        lastErrorMessage = nil
        await refreshSessions()
        await refreshPrimaryData()
    }

    /// Save a manually-entered admin token and reconfigure around it.
    func saveAdminToken(_ token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try SecureTokenStore.shared.saveToken(trimmed, kind: .admin)
        rebuildClients(baseURL: apiClient.baseURL, apiToken: SecureTokenStore.shared.readEffectiveToken())
        await loadCurrentUser()
        await refreshPrimaryData()
    }

    /// Resolve the current identity from /auth/me on launch / after config.
    func loadCurrentUser() async {
        let token = SecureTokenStore.shared.readEffectiveToken()
        guard token != nil else {
            authUser = nil
            isAdminSession = false
            currentSessionID = nil
            return
        }
        isResolvingAuth = true
        defer { isResolvingAuth = false }
        do {
            let me = try await apiClient.fetchMe()
            if me.admin == true {
                isAdminSession = true
                authUser = nil
                currentSessionID = nil
            } else if let user = me.user {
                authUser = user
                isAdminSession = false
                currentSessionID = me.session?.id
            } else {
                authUser = nil
                isAdminSession = false
                currentSessionID = nil
            }
        } catch {
            if Self.isUnauthorized(error) {
                // Bad / expired session token — drop it but keep any admin token.
                try? SecureTokenStore.shared.clear(kind: .session)
                authUser = nil
                currentSessionID = nil
                rebuildClients(baseURL: apiClient.baseURL, apiToken: SecureTokenStore.shared.readEffectiveToken())
            } else {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshSessions() async {
        guard authUser != nil else {
            activeSessions = []
            return
        }
        do {
            activeSessions = try await apiClient.listSessions()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func logout() async {
        do {
            try await apiClient.logout()
        } catch {
            // Even if the server call fails, clear locally so the user is out.
            lastErrorMessage = error.localizedDescription
        }
        try? SecureTokenStore.shared.clear(kind: .session)
        authUser = nil
        isAdminSession = false
        activeSessions = []
        currentSessionID = nil
        rebuildClients(baseURL: apiClient.baseURL, apiToken: SecureTokenStore.shared.readEffectiveToken())
        #if canImport(CoreSpotlight)
        await SpotlightIndexer.shared.clear()
        #endif
    }

    /// Clear the admin token and return to a signed-out state.
    func exitAdminMode() async {
        try? SecureTokenStore.shared.clear(kind: .admin)
        isAdminSession = false
        authUser = nil
        activeSessions = []
        currentSessionID = nil
        rebuildClients(baseURL: apiClient.baseURL, apiToken: SecureTokenStore.shared.readEffectiveToken())
    }

    func revokeSession(_ id: String) async throws {
        try await apiClient.revokeSession(id)
        if id == currentSessionID {
            await logout()
        } else {
            await refreshSessions()
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
        // One-shot v1.1 → v1.2 keychain migration: move a legacy
        // linofinance.apiToken into the admin slot. Guarded by a UserDefaults
        // flag so it runs at most once.
        if !UserDefaults.standard.bool(forKey: "linofinance.tokenMigrated.v1_2") {
            SecureTokenStore.shared.migrateLegacyTokenIfNeeded()
            UserDefaults.standard.set(true, forKey: "linofinance.tokenMigrated.v1_2")
        }
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["LINOFINANCE_API_TOKEN"], !value.isEmpty {
            return value
        }
        if let value = SecureTokenStore.shared.readEffectiveToken(), !value.isEmpty {
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

    /// True when the error is an HTTP 401 from the API. Matches on the typed
    /// `APIError.badStatus` status code rather than the localized message text
    /// (audit 2.11): the old `"API 401"` substring match broke as soon as the
    /// error copy was localized or reworded.
    nonisolated static func isUnauthorized(_ error: Error) -> Bool {
        if case APIError.badStatus(401, _) = error {
            return true
        }
        return false
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
