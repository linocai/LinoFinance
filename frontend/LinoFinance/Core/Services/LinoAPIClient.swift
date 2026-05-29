import Foundation

struct LinoAPIClient {
    let baseURL: URL
    let authToken: String?
    var urlSession: URLSession = .shared

    init(baseURL: URL, authToken: String? = nil, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.authToken = authToken?.isEmpty == false ? authToken : nil
        self.urlSession = urlSession
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = DateFormatter.linoAPIDate.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.linoAPI.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.linoAPIPlain.date(from: value) {
                return date
            }
            if let date = DateFormatter.linoAPIDateTime.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date string: \(value)"
            )
        }
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .formatted(.linoAPIDate)
        return encoder
    }()

    func health() async throws -> AppHealthDTO {
        try await get("health")
    }

    func fetchDashboardSummary() async throws -> DashboardSummaryDTO {
        try await get("dashboard/summary")
    }

    func listAccounts() async throws -> [AccountDTO] {
        try await get("accounts")
    }

    func createAccount(_ request: AccountCreateRequest) async throws -> AccountDTO {
        try await post("accounts", body: request)
    }

    func listCategories() async throws -> [CategoryDTO] {
        try await get("categories")
    }

    func createCategory(_ request: CategoryCreateRequest) async throws -> CategoryDTO {
        try await post("categories", body: request)
    }

    func listCurrencyRates() async throws -> [CurrencyRateDTO] {
        try await get("currency-rates")
    }

    func createCurrencyRate(_ request: CurrencyRateCreateRequest) async throws -> CurrencyRateDTO {
        try await post("currency-rates", body: request)
    }

    func listEntries() async throws -> [EntryDTO] {
        try await get("entries")
    }

    func createEntry(_ request: EntryCreateRequest) async throws -> EntryDTO {
        try await post("entries", body: request)
    }

    func confirmEntry(_ id: String) async throws -> EntryDTO {
        try await post("entries/\(id)/confirm")
    }

    func voidEntry(_ id: String) async throws -> EntryDTO {
        try await post("entries/\(id)/void")
    }

    func listCashFlowItems(
        status: String? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        includeCancelled: Bool = false
    ) async throws -> [CashFlowItemDTO] {
        var query: [URLQueryItem] = []
        if let status {
            query.append(URLQueryItem(name: "status", value: status))
        }
        if let dateFrom {
            query.append(URLQueryItem(name: "date_from", value: DateFormatter.linoAPIDate.string(from: dateFrom)))
        }
        if let dateTo {
            query.append(URLQueryItem(name: "date_to", value: DateFormatter.linoAPIDate.string(from: dateTo)))
        }
        if includeCancelled {
            query.append(URLQueryItem(name: "include_cancelled", value: "true"))
        }
        return try await get("cash-flow-items", queryItems: query)
    }

    func createCashFlowItem(_ request: CashFlowItemCreateRequest) async throws -> CashFlowItemDTO {
        try await post("cash-flow-items", body: request)
    }

    func updateCashFlowItem(_ id: String, request: CashFlowItemUpdateRequest) async throws -> CashFlowItemDTO {
        try await patch("cash-flow-items/\(id)", body: request)
    }

    func confirmCashFlowItem(_ id: String) async throws -> CashFlowItemDTO {
        try await post("cash-flow-items/\(id)/confirm")
    }

    func cancelCashFlowItem(_ id: String) async throws -> CashFlowItemDTO {
        try await post("cash-flow-items/\(id)/cancel")
    }

    func settleCashFlowItem(_ id: String, request: CashFlowSettleRequest) async throws -> CashFlowSettleDTO {
        try await post("cash-flow-items/\(id)/settle", body: request)
    }

    func listReimbursementClaims(status: String? = nil) async throws -> [ReimbursementClaimDTO] {
        let query = status.map { [URLQueryItem(name: "status", value: $0)] } ?? []
        return try await get("reimbursement-claims", queryItems: query)
    }

    func createReimbursementClaim(_ request: ReimbursementClaimCreateRequest) async throws -> ReimbursementClaimDTO {
        try await post("reimbursement-claims", body: request)
    }

    func submitReimbursementClaim(_ id: String) async throws -> ReimbursementClaimDTO {
        try await post("reimbursement-claims/\(id)/submit")
    }

    func approveReimbursementClaim(_ id: String) async throws -> ReimbursementClaimDTO {
        try await post("reimbursement-claims/\(id)/approve")
    }

    func rejectReimbursementClaim(_ id: String) async throws -> ReimbursementClaimDTO {
        try await post("reimbursement-claims/\(id)/reject")
    }

    func abandonReimbursementClaim(_ id: String) async throws -> ReimbursementClaimDTO {
        try await post("reimbursement-claims/\(id)/abandon")
    }

    func markReimbursementReceived(_ id: String, request: ReimbursementReceiveRequest) async throws -> ReimbursementReceiveDTO {
        try await post("reimbursement-claims/\(id)/mark-received", body: request)
    }

    func listAttachments(ownerType: String, ownerID: String) async throws -> [AttachmentDTO] {
        try await get(
            "attachments",
            queryItems: [
                URLQueryItem(name: "owner_type", value: ownerType),
                URLQueryItem(name: "owner_id", value: ownerID)
            ]
        )
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
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = request(for: "attachments")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: [
                "owner_type": ownerType,
                "owner_id": ownerID,
                "uploaded_by": uploadedBy ?? "",
                "note": note ?? ""
            ],
            fileField: "file",
            filename: filename,
            contentType: contentType,
            data: data
        )
        return try await send(request)
    }

    func downloadAttachment(_ id: String) async throws -> Data {
        try await sendData(request(for: "attachments/\(id)"))
    }

    func deleteAttachment(_ id: String) async throws {
        try await delete("attachments/\(id)")
    }

    func listStatementCycles(creditAccountID: String? = nil) async throws -> [CreditStatementCycleDTO] {
        let query = creditAccountID.map { [URLQueryItem(name: "credit_account_id", value: $0)] } ?? []
        return try await get("credit-statement-cycles", queryItems: query)
    }

    func createStatementCycle(_ request: CreditStatementCycleCreateRequest) async throws -> CreditStatementCycleDTO {
        try await post("credit-statement-cycles", body: request)
    }

    func listInstallmentPlans() async throws -> [InstallmentPlanDTO] {
        try await get("installment-plans")
    }

    func createInstallmentPlan(_ request: InstallmentPlanCreateRequest) async throws -> InstallmentPlanDTO {
        try await post("installment-plans", body: request)
    }

    func cancelInstallmentPlan(_ id: String) async throws -> InstallmentPlanDTO {
        try await post("installment-plans/\(id)/cancel")
    }

    func markInstallmentPaidOff(_ id: String) async throws -> InstallmentPlanDTO {
        try await post("installment-plans/\(id)/mark-paid-off")
    }

    func markInstallmentEarlyPaidOff(_ id: String) async throws -> InstallmentPlanDTO {
        try await post("installment-plans/\(id)/mark-early-paid-off")
    }

    func listSubscriptionRules() async throws -> [SubscriptionRuleDTO] {
        try await get("subscription-rules")
    }

    func createSubscriptionRule(_ request: SubscriptionRuleCreateRequest) async throws -> SubscriptionRuleDTO {
        try await post("subscription-rules", body: request)
    }

    func pauseSubscriptionRule(_ id: String) async throws -> SubscriptionRuleDTO {
        try await post("subscription-rules/\(id)/pause")
    }

    func resumeSubscriptionRule(_ id: String) async throws -> SubscriptionRuleDTO {
        try await post("subscription-rules/\(id)/resume")
    }

    func cancelSubscriptionRule(_ id: String) async throws -> SubscriptionRuleDTO {
        try await post("subscription-rules/\(id)/cancel")
    }

    func generateNextSubscriptionCashFlow(_ id: String) async throws -> SubscriptionRuleDTO {
        try await post("subscription-rules/\(id)/generate-next")
    }

    func monthlyOverviewReport(dateFrom: Date? = nil, dateTo: Date? = nil) async throws -> MonthlyOverviewReportDTO {
        var query: [URLQueryItem] = []
        if let dateFrom {
            query.append(URLQueryItem(name: "date_from", value: DateFormatter.linoAPIDate.string(from: dateFrom)))
        }
        if let dateTo {
            query.append(URLQueryItem(name: "date_to", value: DateFormatter.linoAPIDate.string(from: dateTo)))
        }
        return try await get("reports/monthly-overview", queryItems: query)
    }

    func categoryExpensesReport() async throws -> CategoryExpenseReportDTO {
        try await get("reports/category-expenses")
    }

    func cashFlowPressureReport(dateFrom: Date? = nil, dateTo: Date? = nil) async throws -> CashFlowPressureReportDTO {
        var query: [URLQueryItem] = []
        if let dateFrom {
            query.append(URLQueryItem(name: "date_from", value: DateFormatter.linoAPIDate.string(from: dateFrom)))
        }
        if let dateTo {
            query.append(URLQueryItem(name: "date_to", value: DateFormatter.linoAPIDate.string(from: dateTo)))
        }
        return try await get("reports/cash-flow-pressure", queryItems: query)
    }

    func creditLiabilityTrendReport() async throws -> CreditLiabilityTrendReportDTO {
        try await get("reports/credit-liability-trend")
    }

    func reimbursementReport(view: String = "personal_net") async throws -> ReimbursementReportDTO {
        try await get("reports/reimbursements", queryItems: [URLQueryItem(name: "view", value: view)])
    }

    func subscriptionReport() async throws -> SubscriptionReportDTO {
        try await get("reports/subscriptions")
    }

    func listCSVExports() async throws -> ExportDatasetListDTO {
        try await get("exports/csv")
    }

    func downloadCSV(dataset: String) async throws -> Data {
        let request = request(for: "exports/csv/\(dataset)")
        return try await sendData(request)
    }

    func search(query: String, limit: Int = 20, types: [String] = []) async throws -> SearchResponseDTO {
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if !types.isEmpty {
            queryItems.append(URLQueryItem(name: "types", value: types.joined(separator: ",")))
        }
        return try await get("search", queryItems: queryItems)
    }

    func aiConfig() async throws -> AIConfigDTO {
        try await get("ai/config")
    }

    func listAIPlans(
        status: String? = nil,
        relatedType: String? = nil,
        relatedTo: String? = nil
    ) async throws -> [AIPlanDTO] {
        var query: [URLQueryItem] = []
        if let status {
            query.append(URLQueryItem(name: "status", value: status))
        }
        if let relatedType {
            query.append(URLQueryItem(name: "related_type", value: relatedType))
        }
        if let relatedTo {
            query.append(URLQueryItem(name: "related_to", value: relatedTo))
        }
        return try await get("ai/plans", queryItems: query)
    }

    func createAIPlan(_ request: AIPlanCreateRequest) async throws -> AIPlanDTO {
        try await post("ai/plans", body: request)
    }

    func approveAIPlan(_ id: String, note: String? = nil) async throws -> AIPlanDTO {
        try await post("ai/plans/\(id)/approve", body: AINoteRequest(note: note))
    }

    func rejectAIPlan(_ id: String, note: String? = nil) async throws -> AIPlanDTO {
        try await post("ai/plans/\(id)/reject", body: AINoteRequest(note: note))
    }

    func executeAIPlan(_ id: String, strongConfirm: String? = nil) async throws -> AIPlanDTO {
        try await post("ai/plans/\(id)/execute", body: AIExecuteRequest(strongConfirm: strongConfirm))
    }

    func rollbackAIAction(_ id: String) async throws -> AIActionDTO {
        try await post("ai/actions/\(id)/rollback")
    }

    func listAIMemos(period: String? = nil) async throws -> AIMemoListResponseDTO {
        let query = period.map { [URLQueryItem(name: "period", value: $0)] } ?? []
        return try await get("ai/memos", queryItems: query)
    }

    func generateAIMemo(_ request: AIMemoGenerateRequest, tone: String? = nil) async throws -> AIMemoDTO {
        let query = tone.map { [URLQueryItem(name: "tone", value: $0)] } ?? []
        return try await post("ai/memos/generate", queryItems: query, body: request)
    }

    func patchAIMemo(_ id: String, request: AIMemoPatchRequest) async throws -> AIMemoDTO {
        try await patch("ai/memos/\(id)", body: request)
    }

    func archiveAIMemo(_ id: String) async throws {
        try await delete("ai/memos/\(id)")
    }

    func listReconciliationAccounts() async throws -> ReconciliationAccountsResponseDTO {
        try await get("reconciliation/accounts")
    }

    func createAccountAdjustment(_ request: AccountAdjustmentCreateRequest) async throws -> AccountAdjustmentDTO {
        try await post("reconciliation/adjustments", body: request)
    }

    func recordDailyPnL(accountID: String, request: DailyPnLCreateRequest) async throws -> DailyPnLReadDTO {
        try await post("accounts/\(accountID)/daily-pnl", body: request)
    }

    func listNotificationRules(status: String? = nil, ruleType: String? = nil) async throws -> [NotificationRuleDTO] {
        var query: [URLQueryItem] = []
        if let status {
            query.append(URLQueryItem(name: "status", value: status))
        }
        if let ruleType {
            query.append(URLQueryItem(name: "rule_type", value: ruleType))
        }
        return try await get("notification-rules", queryItems: query)
    }

    func createNotificationRule(_ request: NotificationRuleCreateRequest) async throws -> NotificationRuleDTO {
        try await post("notification-rules", body: request)
    }

    func pauseNotificationRule(_ id: String) async throws -> NotificationRuleDTO {
        try await post("notification-rules/\(id)/pause")
    }

    func resumeNotificationRule(_ id: String) async throws -> NotificationRuleDTO {
        try await post("notification-rules/\(id)/resume")
    }

    func cancelNotificationRule(_ id: String) async throws -> NotificationRuleDTO {
        try await post("notification-rules/\(id)/cancel")
    }

    func registerPushDevice(_ request: PushDeviceRegisterRequest) async throws -> PushDeviceDTO {
        try await post("push/devices", body: request)
    }

    func disablePushDevice(_ id: String) async throws {
        try await delete("push/devices/\(id)")
    }

    // MARK: - Auth (Sign in with Apple, v1.2)

    /// Exchanges an Apple identity_token for a LinoFinance session token.
    /// Deliberately sends NO Authorization header — this is the bootstrap and
    /// there is no token yet.
    func signInWithApple(_ request: AppleSignInRequest) async throws -> AppleSignInResponseDTO {
        var urlRequest = self.request(for: "auth/apple", includeAuthHeader: false)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)
        return try await send(urlRequest)
    }

    func fetchMe() async throws -> AuthMeResponseDTO {
        try await get("auth/me")
    }

    func logout() async throws {
        var request = request(for: "auth/logout")
        request.httpMethod = "POST"
        _ = try await sendData(request)
    }

    func listSessions() async throws -> [AuthSessionDTO] {
        let response: AuthSessionListResponseDTO = try await get("auth/sessions")
        return response.items
    }

    func revokeSession(_ id: String) async throws {
        try await delete("auth/sessions/\(id)")
    }

    func listAuditLogs(
        targetType: String? = nil,
        targetID: String? = nil,
        limit: Int? = nil
    ) async throws -> [AuditLogDTO] {
        var query: [URLQueryItem] = []
        if let targetType {
            query.append(URLQueryItem(name: "target_type", value: targetType))
        }
        if let targetID {
            query.append(URLQueryItem(name: "target_id", value: targetID))
        }
        if let limit {
            query.append(URLQueryItem(name: "limit", value: "\(limit)"))
        }
        return try await get("audit-logs", queryItems: query)
    }

    private func get<Response: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Response {
        let request = request(for: path, queryItems: queryItems)
        return try await send(request)
    }

    private func post<Response: Decodable>(_ path: String) async throws -> Response {
        var request = request(for: path)
        request.httpMethod = "POST"
        return try await send(request)
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem],
        body: Request
    ) async throws -> Response {
        var request = request(for: path, queryItems: queryItems)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ path: String,
        body: Request
    ) async throws -> Response {
        var request = request(for: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    private func patch<Request: Encodable, Response: Decodable>(
        _ path: String,
        body: Request
    ) async throws -> Response {
        var request = request(for: path)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    private func delete(_ path: String) async throws {
        var request = request(for: path)
        request.httpMethod = "DELETE"
        _ = try await sendData(request)
    }

    private func request(
        for path: String,
        queryItems: [URLQueryItem] = [],
        includeAuthHeader: Bool = true
    ) -> URLRequest {
        var request = URLRequest(url: url(for: path, queryItems: queryItems))
        if includeAuthHeader, let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func url(for path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await sendData(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let errorBody = try? decoder.decode(APIErrorBody.self, from: data)
                throw APIError.badStatus(httpResponse.statusCode, errorBody?.message)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private static func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        filename: String,
        contentType: String,
        data: Data
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        for (name, value) in fields where !value.isEmpty {
            body.append("--\(boundary)\(lineBreak)")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
            body.append("\(value)\(lineBreak)")
        }
        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\(lineBreak)")
        body.append("Content-Type: \(contentType)\(lineBreak)\(lineBreak)")
        body.append(data)
        body.append(lineBreak)
        body.append("--\(boundary)--\(lineBreak)")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(contentsOf: string.utf8)
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidResponse
    case badStatus(Int, String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "API 返回了无法识别的响应。"
        case .badStatus(let status, let detail):
            return detail.map { "API \(status)：\($0)" } ?? "API 请求失败：\(status)"
        case .decoding(let message):
            return "API 数据解析失败：\(message)"
        case .transport:
            return "无法连接 API。请确认后端已经启动，或检查域名/API Token 配置。"
        }
    }
}

private struct APIErrorBody: Decodable {
    let detail: JSONValueDTO?

    var message: String? {
        detail?.displayText
    }
}

private extension ISO8601DateFormatter {
    static let linoAPI: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let linoAPIPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
