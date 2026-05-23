import Foundation

struct FinanceRepository {
    let apiClient: LinoAPIClient

    func dashboardSummary() async throws -> DashboardSummaryDTO {
        try await apiClient.fetchDashboardSummary()
    }

    func accounts() async throws -> [AccountDTO] {
        try await apiClient.listAccounts()
    }

    func createAccount(_ request: AccountCreateRequest) async throws -> AccountDTO {
        try await apiClient.createAccount(request)
    }

    func categories() async throws -> [CategoryDTO] {
        try await apiClient.listCategories()
    }

    func createCategory(_ request: CategoryCreateRequest) async throws -> CategoryDTO {
        try await apiClient.createCategory(request)
    }

    func currencyRates() async throws -> [CurrencyRateDTO] {
        try await apiClient.listCurrencyRates()
    }

    func createCurrencyRate(_ request: CurrencyRateCreateRequest) async throws -> CurrencyRateDTO {
        try await apiClient.createCurrencyRate(request)
    }

    func entries() async throws -> [EntryDTO] {
        try await apiClient.listEntries()
    }

    func createEntry(_ request: EntryCreateRequest) async throws -> EntryDTO {
        try await apiClient.createEntry(request)
    }

    func confirmEntry(_ id: String) async throws -> EntryDTO {
        try await apiClient.confirmEntry(id)
    }

    func voidEntry(_ id: String) async throws -> EntryDTO {
        try await apiClient.voidEntry(id)
    }

    func cashFlowItems(includeCancelled: Bool = false) async throws -> [CashFlowItemDTO] {
        try await apiClient.listCashFlowItems(includeCancelled: includeCancelled)
    }

    func createCashFlowItem(_ request: CashFlowItemCreateRequest) async throws -> CashFlowItemDTO {
        try await apiClient.createCashFlowItem(request)
    }

    func confirmCashFlowItem(_ id: String) async throws -> CashFlowItemDTO {
        try await apiClient.confirmCashFlowItem(id)
    }

    func cancelCashFlowItem(_ id: String) async throws -> CashFlowItemDTO {
        try await apiClient.cancelCashFlowItem(id)
    }

    func settleCashFlowItem(_ id: String, request: CashFlowSettleRequest) async throws -> CashFlowSettleDTO {
        try await apiClient.settleCashFlowItem(id, request: request)
    }

    func reimbursementClaims() async throws -> [ReimbursementClaimDTO] {
        try await apiClient.listReimbursementClaims()
    }

    func createReimbursementClaim(_ request: ReimbursementClaimCreateRequest) async throws -> ReimbursementClaimDTO {
        try await apiClient.createReimbursementClaim(request)
    }

    func submitReimbursementClaim(_ id: String) async throws -> ReimbursementClaimDTO {
        try await apiClient.submitReimbursementClaim(id)
    }

    func approveReimbursementClaim(_ id: String) async throws -> ReimbursementClaimDTO {
        try await apiClient.approveReimbursementClaim(id)
    }

    func rejectReimbursementClaim(_ id: String) async throws -> ReimbursementClaimDTO {
        try await apiClient.rejectReimbursementClaim(id)
    }

    func abandonReimbursementClaim(_ id: String) async throws -> ReimbursementClaimDTO {
        try await apiClient.abandonReimbursementClaim(id)
    }

    func markReimbursementReceived(_ id: String, request: ReimbursementReceiveRequest) async throws -> ReimbursementReceiveDTO {
        try await apiClient.markReimbursementReceived(id, request: request)
    }

    func attachments(ownerType: String, ownerID: String) async throws -> [AttachmentDTO] {
        try await apiClient.listAttachments(ownerType: ownerType, ownerID: ownerID)
    }

    func uploadAttachment(
        ownerType: String,
        ownerID: String,
        filename: String,
        contentType: String,
        data: Data,
        uploadedBy: String? = "app",
        note: String? = nil
    ) async throws -> AttachmentDTO {
        try await apiClient.uploadAttachment(
            ownerType: ownerType,
            ownerID: ownerID,
            filename: filename,
            contentType: contentType,
            data: data,
            uploadedBy: uploadedBy,
            note: note
        )
    }

    func downloadAttachment(_ id: String) async throws -> Data {
        try await apiClient.downloadAttachment(id)
    }

    func deleteAttachment(_ id: String) async throws {
        try await apiClient.deleteAttachment(id)
    }

    func statementCycles() async throws -> [CreditStatementCycleDTO] {
        try await apiClient.listStatementCycles()
    }

    func createStatementCycle(_ request: CreditStatementCycleCreateRequest) async throws -> CreditStatementCycleDTO {
        try await apiClient.createStatementCycle(request)
    }

    func installmentPlans() async throws -> [InstallmentPlanDTO] {
        try await apiClient.listInstallmentPlans()
    }

    func createInstallmentPlan(_ request: InstallmentPlanCreateRequest) async throws -> InstallmentPlanDTO {
        try await apiClient.createInstallmentPlan(request)
    }

    func cancelInstallmentPlan(_ id: String) async throws -> InstallmentPlanDTO {
        try await apiClient.cancelInstallmentPlan(id)
    }

    func markInstallmentPaidOff(_ id: String) async throws -> InstallmentPlanDTO {
        try await apiClient.markInstallmentPaidOff(id)
    }

    func markInstallmentEarlyPaidOff(_ id: String) async throws -> InstallmentPlanDTO {
        try await apiClient.markInstallmentEarlyPaidOff(id)
    }

    func subscriptionRules() async throws -> [SubscriptionRuleDTO] {
        try await apiClient.listSubscriptionRules()
    }

    func createSubscriptionRule(_ request: SubscriptionRuleCreateRequest) async throws -> SubscriptionRuleDTO {
        try await apiClient.createSubscriptionRule(request)
    }

    func pauseSubscriptionRule(_ id: String) async throws -> SubscriptionRuleDTO {
        try await apiClient.pauseSubscriptionRule(id)
    }

    func resumeSubscriptionRule(_ id: String) async throws -> SubscriptionRuleDTO {
        try await apiClient.resumeSubscriptionRule(id)
    }

    func cancelSubscriptionRule(_ id: String) async throws -> SubscriptionRuleDTO {
        try await apiClient.cancelSubscriptionRule(id)
    }

    func generateNextSubscriptionCashFlow(_ id: String) async throws -> SubscriptionRuleDTO {
        try await apiClient.generateNextSubscriptionCashFlow(id)
    }

    func refreshReports(cashFlowFrom: Date? = nil, cashFlowTo: Date? = nil) async throws -> ReportsBundle {
        let monthly = try await apiClient.monthlyOverviewReport()
        let categories = try await apiClient.categoryExpensesReport()
        let cashFlow = try await apiClient.cashFlowPressureReport(dateFrom: cashFlowFrom, dateTo: cashFlowTo)
        let credit = try await apiClient.creditLiabilityTrendReport()
        let reimbursement = try await apiClient.reimbursementReport()
        let subscriptions = try await apiClient.subscriptionReport()
        let exports = try await apiClient.listCSVExports()
        return ReportsBundle(
            monthly: monthly,
            categories: categories,
            cashFlow: cashFlow,
            credit: credit,
            reimbursement: reimbursement,
            subscriptions: subscriptions,
            exports: exports.datasets
        )
    }

    func monthlyOverview(dateFrom: Date? = nil, dateTo: Date? = nil) async throws -> MonthlyOverviewReportDTO {
        try await apiClient.monthlyOverviewReport(dateFrom: dateFrom, dateTo: dateTo)
    }

    func downloadCSV(dataset: String) async throws -> Data {
        try await apiClient.downloadCSV(dataset: dataset)
    }

    func search(query: String, limit: Int = 20, types: [String] = []) async throws -> SearchResponseDTO {
        try await apiClient.search(query: query, limit: limit, types: types)
    }

    func aiConfig() async throws -> AIConfigDTO {
        try await apiClient.aiConfig()
    }

    func aiPlans(
        status: String? = nil,
        relatedType: String? = nil,
        relatedTo: String? = nil
    ) async throws -> [AIPlanDTO] {
        try await apiClient.listAIPlans(
            status: status,
            relatedType: relatedType,
            relatedTo: relatedTo
        )
    }

    func createAIPlan(_ request: AIPlanCreateRequest) async throws -> AIPlanDTO {
        try await apiClient.createAIPlan(request)
    }

    func approveAIPlan(_ id: String) async throws -> AIPlanDTO {
        try await apiClient.approveAIPlan(id)
    }

    func rejectAIPlan(_ id: String) async throws -> AIPlanDTO {
        try await apiClient.rejectAIPlan(id)
    }

    func executeAIPlan(_ id: String, strongConfirm: String? = nil) async throws -> AIPlanDTO {
        try await apiClient.executeAIPlan(id, strongConfirm: strongConfirm)
    }

    func rollbackAIAction(_ id: String) async throws -> AIActionDTO {
        try await apiClient.rollbackAIAction(id)
    }

    func aiMemos(period: String? = nil) async throws -> [AIMemoDTO] {
        try await apiClient.listAIMemos(period: period).items
    }

    func generateAIMemo(_ request: AIMemoGenerateRequest, tone: String? = nil) async throws -> AIMemoDTO {
        try await apiClient.generateAIMemo(request, tone: tone)
    }

    func patchAIMemo(_ id: String, request: AIMemoPatchRequest) async throws -> AIMemoDTO {
        try await apiClient.patchAIMemo(id, request: request)
    }

    func archiveAIMemo(_ id: String) async throws {
        try await apiClient.archiveAIMemo(id)
    }

    func reconciliationAccounts() async throws -> ReconciliationAccountsResponseDTO {
        try await apiClient.listReconciliationAccounts()
    }

    func createAccountAdjustment(_ request: AccountAdjustmentCreateRequest) async throws -> AccountAdjustmentDTO {
        try await apiClient.createAccountAdjustment(request)
    }

    func notificationRules() async throws -> [NotificationRuleDTO] {
        try await apiClient.listNotificationRules()
    }

    func createNotificationRule(_ request: NotificationRuleCreateRequest) async throws -> NotificationRuleDTO {
        try await apiClient.createNotificationRule(request)
    }

    func pauseNotificationRule(_ id: String) async throws -> NotificationRuleDTO {
        try await apiClient.pauseNotificationRule(id)
    }

    func resumeNotificationRule(_ id: String) async throws -> NotificationRuleDTO {
        try await apiClient.resumeNotificationRule(id)
    }

    func cancelNotificationRule(_ id: String) async throws -> NotificationRuleDTO {
        try await apiClient.cancelNotificationRule(id)
    }

    func registerPushDevice(_ request: PushDeviceRegisterRequest) async throws -> PushDeviceDTO {
        try await apiClient.registerPushDevice(request)
    }

    func disablePushDevice(_ id: String) async throws {
        try await apiClient.disablePushDevice(id)
    }

    func auditLogs(
        targetType: String? = nil,
        targetID: String? = nil,
        limit: Int? = nil
    ) async throws -> [AuditLogDTO] {
        try await apiClient.listAuditLogs(targetType: targetType, targetID: targetID, limit: limit)
    }
}

struct ReportsBundle: Equatable {
    let monthly: MonthlyOverviewReportDTO
    let categories: CategoryExpenseReportDTO
    let cashFlow: CashFlowPressureReportDTO
    let credit: CreditLiabilityTrendReportDTO
    let reimbursement: ReimbursementReportDTO
    let subscriptions: SubscriptionReportDTO
    let exports: [ExportDatasetDTO]
}
