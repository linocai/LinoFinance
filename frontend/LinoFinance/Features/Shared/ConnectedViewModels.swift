import Foundation
import Observation

@MainActor
@Observable
final class CashFlowViewModel {
    private let repository: FinanceRepository
    var items: [CashFlowItemDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await repository.cashFlowItems().sorted { $0.expectedDate < $1.expectedDate }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func create(_ request: CashFlowItemCreateRequest) async throws {
        _ = try await repository.createCashFlowItem(request)
        try await refresh()
    }

    func create(_ requests: [CashFlowItemCreateRequest]) async throws {
        for request in requests {
            _ = try await repository.createCashFlowItem(request)
        }
        try await refresh()
    }

    func confirm(_ id: String) async throws {
        _ = try await repository.confirmCashFlowItem(id)
        try await refresh()
    }

    func cancel(_ id: String) async throws {
        _ = try await repository.cancelCashFlowItem(id)
        try await refresh()
    }

    func settle(_ id: String, request: CashFlowSettleRequest) async throws {
        _ = try await repository.settleCashFlowItem(id, request: request)
        try await refresh()
    }
}

@MainActor
@Observable
final class ReimbursementsViewModel {
    private let repository: FinanceRepository
    var claims: [ReimbursementClaimDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            claims = try await repository.reimbursementClaims().sorted { $0.expectedDate < $1.expectedDate }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func create(_ request: ReimbursementClaimCreateRequest) async throws {
        _ = try await repository.createReimbursementClaim(request)
        try await refresh()
    }

    func submit(_ id: String) async throws {
        _ = try await repository.submitReimbursementClaim(id)
        try await refresh()
    }

    func approve(_ id: String) async throws {
        _ = try await repository.approveReimbursementClaim(id)
        try await refresh()
    }

    func reject(_ id: String) async throws {
        _ = try await repository.rejectReimbursementClaim(id)
        try await refresh()
    }

    func abandon(_ id: String) async throws {
        _ = try await repository.abandonReimbursementClaim(id)
        try await refresh()
    }

    func markReceived(_ id: String, request: ReimbursementReceiveRequest) async throws {
        _ = try await repository.markReimbursementReceived(id, request: request)
        try await refresh()
    }
}

@MainActor
@Observable
final class CreditViewModel {
    private let repository: FinanceRepository
    var cycles: [CreditStatementCycleDTO] = []
    var installmentPlans: [InstallmentPlanDTO] = []
    var subscriptionRules: [SubscriptionRuleDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            cycles = try await repository.statementCycles().sorted { $0.dueDate < $1.dueDate }
            installmentPlans = try await repository.installmentPlans().sorted { $0.startDate > $1.startDate }
            subscriptionRules = try await repository.subscriptionRules().sorted {
                ($0.nextChargeDate ?? .distantFuture) < ($1.nextChargeDate ?? .distantFuture)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func createCycle(_ request: CreditStatementCycleCreateRequest) async throws {
        _ = try await repository.createStatementCycle(request)
        try await refresh()
    }

    func createInstallmentPlan(_ request: InstallmentPlanCreateRequest) async throws {
        _ = try await repository.createInstallmentPlan(request)
        try await refresh()
    }

    func cancelInstallment(_ id: String) async throws {
        _ = try await repository.cancelInstallmentPlan(id)
        try await refresh()
    }

    func markInstallmentPaidOff(_ id: String, early: Bool = false) async throws {
        if early {
            _ = try await repository.markInstallmentEarlyPaidOff(id)
        } else {
            _ = try await repository.markInstallmentPaidOff(id)
        }
        try await refresh()
    }

    func createSubscription(_ request: SubscriptionRuleCreateRequest) async throws {
        _ = try await repository.createSubscriptionRule(request)
        try await refresh()
    }

    func pauseSubscription(_ id: String) async throws {
        _ = try await repository.pauseSubscriptionRule(id)
        try await refresh()
    }

    func resumeSubscription(_ id: String) async throws {
        _ = try await repository.resumeSubscriptionRule(id)
        try await refresh()
    }

    func cancelSubscription(_ id: String) async throws {
        _ = try await repository.cancelSubscriptionRule(id)
        try await refresh()
    }

    func generateNextSubscription(_ id: String) async throws {
        _ = try await repository.generateNextSubscriptionCashFlow(id)
        try await refresh()
    }
}

@MainActor
@Observable
final class ReportsViewModel {
    private let repository: FinanceRepository
    var bundle: ReportsBundle?
    var isLoading = false
    var errorMessage: String?
    var lastExportPath: String?
    var lastExportURL: URL?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            bundle = try await repository.refreshReports()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func exportCSV(_ dataset: ExportDatasetDTO) async throws -> URL {
        let data = try await repository.downloadCSV(dataset: dataset.name)
#if os(macOS)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
#else
        let downloads = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
#endif
        let url = downloads.appendingPathComponent(dataset.filename)
        try data.write(to: url, options: .atomic)
        lastExportURL = url
        lastExportPath = url.path
        return url
    }
}

@MainActor
@Observable
final class AIWorkspaceViewModel {
    private let repository: FinanceRepository
    var config: AIConfigDTO?
    var plans: [AIPlanDTO] = []
    var auditLogs: [AuditLogDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            config = try await repository.aiConfig()
            plans = try await repository.aiPlans().sorted { $0.id > $1.id }
            auditLogs = try await repository.auditLogs()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func createPlan(sourceText: String) async throws -> AIPlanDTO {
        let plan = try await repository.createAIPlan(AIPlanCreateRequest(sourceText: sourceText))
        try await refresh()
        return plan
    }

    func approve(_ id: String) async throws {
        _ = try await repository.approveAIPlan(id)
        try await refresh()
    }

    func reject(_ id: String) async throws {
        _ = try await repository.rejectAIPlan(id)
        try await refresh()
    }

    func execute(_ id: String, strongConfirm: String? = nil) async throws {
        _ = try await repository.executeAIPlan(id, strongConfirm: strongConfirm)
        try await refresh()
    }

    func rollbackAction(_ id: String) async throws {
        _ = try await repository.rollbackAIAction(id)
        try await refresh()
    }
}

enum AIMemoTone: String, CaseIterable, Identifiable {
    case warm
    case terse
    case playful
    case professional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: "温暖"
        case .terse: "简洁"
        case .playful: "轻松"
        case .professional: "专业"
        }
    }
}

@MainActor
@Observable
final class AIMemoViewModel {
    private let repository: FinanceRepository
    var memos: [AIMemoDTO] = []
    var selectedMemo: AIMemoDTO?
    var draftSummary = ""
    var isPreviewing = false
    var isLoading = false
    var errorMessage: String?
    var lastExportURL: URL?
    var lastExportPath: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh(period: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            memos = try await repository.aiMemos(period: period)
                .sorted { $0.periodStart > $1.periodStart }
            if let selectedMemo, let refreshed = memos.first(where: { $0.id == selectedMemo.id }) {
                select(refreshed)
            } else if selectedMemo == nil {
                select(memos.first)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func select(_ memo: AIMemoDTO?) {
        selectedMemo = memo
        draftSummary = memo?.summary ?? ""
    }

    func generate(start: Date, end: Date, tone: AIMemoTone? = nil, status: String = "draft") async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            let memo = try await repository.generateAIMemo(
                AIMemoGenerateRequest(periodStart: start, periodEnd: end, status: status),
                tone: tone?.rawValue
            )
            upsert(memo)
            select(memo)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func saveSelected(status: String? = nil) async throws {
        guard let selectedMemo else { return }
        let memo = try await repository.patchAIMemo(
            selectedMemo.id,
            request: AIMemoPatchRequest(
                summary: draftSummary,
                status: status ?? selectedMemo.status
            )
        )
        upsert(memo)
        select(memo)
    }

    func archiveSelected() async throws {
        guard let selectedMemo else { return }
        try await repository.archiveAIMemo(selectedMemo.id)
        memos.removeAll { $0.id == selectedMemo.id }
        select(memos.first)
    }

    func markExported(_ url: URL) {
        lastExportURL = url
        lastExportPath = url.path
    }

    private func upsert(_ memo: AIMemoDTO) {
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index] = memo
        } else {
            memos.insert(memo, at: 0)
        }
        memos.sort { $0.periodStart > $1.periodStart }
    }
}

enum ReconciliationFilter: String, CaseIterable, Identifiable {
    case all
    case driftOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .driftOnly: "仅差异"
        }
    }
}

@MainActor
@Observable
final class ReconciliationViewModel {
    private let repository: FinanceRepository
    var response: ReconciliationAccountsResponseDTO?
    var filter: ReconciliationFilter = .all
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    var rows: [ReconciliationAccountDTO] {
        let items = response?.items ?? []
        switch filter {
        case .all:
            return items
        case .driftOnly:
            return items.filter(\.needsAdjustment)
        }
    }

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await repository.reconciliationAccounts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func submitAdjustment(
        accountID: String,
        actualAmount: DecimalValue,
        reason: String,
        note: String?
    ) async throws {
        do {
            _ = try await repository.createAccountAdjustment(
                AccountAdjustmentCreateRequest(
                    accountId: accountID,
                    actualAmount: actualAmount,
                    reason: reason,
                    note: note?.isEmpty == false ? note : nil
                )
            )
            successMessage = "已提交并写入审计日志"
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}

@MainActor
@Observable
final class NotificationsViewModel {
    private let repository: FinanceRepository
    var rules: [NotificationRuleDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            rules = try await repository.notificationRules().sorted {
                ($0.nextTriggerDate ?? .distantFuture) < ($1.nextTriggerDate ?? .distantFuture)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func create(_ request: NotificationRuleCreateRequest) async throws {
        _ = try await repository.createNotificationRule(request)
        try await refresh()
    }

    func pause(_ id: String) async throws {
        _ = try await repository.pauseNotificationRule(id)
        try await refresh()
    }

    func resume(_ id: String) async throws {
        _ = try await repository.resumeNotificationRule(id)
        try await refresh()
    }

    func cancel(_ id: String) async throws {
        _ = try await repository.cancelNotificationRule(id)
        try await refresh()
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    private let repository: FinanceRepository
    var health: AppHealthDTO?
    var aiConfig: AIConfigDTO?
    var rates: [CurrencyRateDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: LinoAPIClient) {
        repository = FinanceRepository(apiClient: apiClient)
    }

    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            health = try await repository.apiClient.health()
            if repository.apiClient.authToken == nil {
                aiConfig = nil
                rates = []
            } else {
                aiConfig = try await repository.aiConfig()
                rates = try await repository.currencyRates().sorted { $0.date > $1.date }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func createRate(_ request: CurrencyRateCreateRequest) async throws {
        _ = try await repository.createCurrencyRate(request)
        try await refresh()
    }
}
