import Foundation
#if canImport(AppIntents)
import AppIntents
#endif

struct AppHealthDTO: Decodable, Equatable {
    let status: String
    let app: String
    let version: String
    let environment: String
    let authRequired: Bool?
    let rateLimitEnabled: Bool?
    let apnsUseSandbox: Bool?
    let apnsDryRun: Bool?
}

struct CurrencyAmountDTO: Decodable, Equatable, Hashable {
    let currency: CurrencyCode
    let amount: DecimalValue
}

struct DashboardSummaryDTO: Decodable, Equatable {
    let baseCurrency: String
    let balanceTotalCny: DecimalValue
    let creditLiabilityTotalCny: DecimalValue
    let netWorthCny: DecimalValue
    let draftEntryCount: Int
    let confirmedEntryCount: Int
    let voidedEntryCount: Int

    // New in v1.1.6 — optional so an older backend still decodes.
    let investmentTotalCny: DecimalValue?
    let investmentTotalByCurrency: [CurrencyAmountDTO]?
    let todayPnlByCurrency: [CurrencyAmountDTO]?
    let disposable30dByCurrency: [CurrencyAmountDTO]?
    let cashFlow30dByCurrency: [CurrencyAmountDTO]?

    // New in v1.4.0 P2 — per-currency net-worth breakdown (CNY always present,
    // other currencies only when non-zero). Optional so an older backend that
    // does not emit them still decodes.
    let balanceTotalByCurrency: [CurrencyAmountDTO]?
    let creditLiabilityByCurrency: [CurrencyAmountDTO]?
    let netWorthByCurrency: [CurrencyAmountDTO]?

    // The global decoder uses .convertFromSnakeCase, which first transforms
    // the JSON key and *then* matches it against CodingKeys raw values.
    // For digit+letter segments the transformer capitalises the letter
    // (`"30d".capitalized == "30D"`), so e.g. `disposable_30d_by_currency`
    // ends up as `disposable30DByCurrency` (capital D). To recover the
    // small-d Swift name we want, the CodingKeys raw values must be the
    // transformer's *output*, not the snake-case source.
    private enum CodingKeys: String, CodingKey {
        case baseCurrency
        case balanceTotalCny
        case creditLiabilityTotalCny
        case netWorthCny
        case draftEntryCount
        case confirmedEntryCount
        case voidedEntryCount
        case investmentTotalCny
        case investmentTotalByCurrency
        case todayPnlByCurrency
        case disposable30dByCurrency = "disposable30DByCurrency"
        case cashFlow30dByCurrency = "cashFlow30DByCurrency"
        // All-letter snake_case keys map cleanly through .convertFromSnakeCase,
        // so the CodingKeys raw values are the default camelCase names.
        case balanceTotalByCurrency
        case creditLiabilityByCurrency
        case netWorthByCurrency
    }
}

struct AccountDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let name: String
    let type: AccountType
    let currency: CurrencyCode
    let currentBalance: DecimalValue
    let currentLiability: DecimalValue
    let includeInNetWorth: Bool
    let status: String
    let displayOrder: Int
    let creditLimit: DecimalValue?
    let statementDay: Int?
    let dueDay: Int?
    let minimumPayment: DecimalValue?
    let notes: String?
}

struct CategoryDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let name: String
    let parentId: String?
    let type: CategoryType
    let isActive: Bool
    let displayOrder: Int
}

struct CurrencyRateDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let fromCurrency: CurrencyCode
    let toCurrency: CurrencyCode
    let rate: DecimalValue
    let date: Date
    let source: String
    let note: String?
}

struct EntryDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let title: String
    let entryType: String
    let date: Date
    let startDate: Date?
    let endDate: Date?
    let status: EntryStatus
    let note: String?
    let createdBy: String
    let categoryLines: [EntryCategoryLineDTO]
    let accountMovements: [AccountMovementDTO]
}

struct EntryCategoryLineDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let entryId: String
    let categoryId: String
    let direction: CategoryDirection
    let amount: DecimalValue
    let currency: CurrencyCode
    let exchangeRateId: String?
    let convertedCnyAmount: DecimalValue?
    let reimbursableFlag: Bool
    let reimbursementPayer: String?
    let reimbursementExpectedDate: Date?
    let reimbursementStatus: String?
    let note: String?
}

struct AccountMovementDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let entryId: String
    let accountId: String
    let statementCycleId: String?
    let movementType: MovementType
    let amount: DecimalValue
    let currency: CurrencyCode
    let exchangeRateId: String?
    let convertedCnyAmount: DecimalValue?
    let note: String?
}

struct CashFlowItemDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let title: String
    let direction: String
    let cashFlowType: String
    let amount: DecimalValue
    let currency: CurrencyCode
    let exchangeRateId: String?
    let convertedCnyAmount: DecimalValue?
    let expectedDate: Date
    let accountId: String?
    let categoryId: String?
    let recurrenceRule: String?
    let status: String
    let linkedEntryId: String?
    let linkedReimbursementId: String?
    let linkedInstallmentPlanId: String?
    let linkedSubscriptionRuleId: String?
    let linkedStatementCycleId: String?
    let note: String?
}

struct CashFlowSettleDTO: Decodable, Equatable {
    let cashFlowItem: CashFlowItemDTO
    let entry: EntryDTO
}

struct ReimbursementClaimDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let linkedEntryId: String
    let linkedEntryLineId: String?
    let amount: DecimalValue
    let currency: CurrencyCode
    let exchangeRateId: String?
    let convertedCnyAmount: DecimalValue?
    let payer: String
    let expectedDate: Date
    let actualReceivedDate: Date?
    let receivedAccountId: String?
    let receivedEntryId: String?
    let status: String
    let cashFlowItemId: String?
    let invoiceAttachmentIds: [String]?
    let note: String?
}

struct ReimbursementReceiveDTO: Decodable, Equatable {
    let reimbursementClaim: ReimbursementClaimDTO
    let entry: EntryDTO
}

struct AttachmentDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let ownerType: String
    let ownerId: String
    let filename: String
    let contentType: String
    let sizeBytes: Int
    let checksumSha256: String
    let storageKey: String
    let uploadedBy: String?
    let note: String?
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct CreditStatementCycleDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let creditAccountId: String
    let cycleStartDate: Date
    let cycleEndDate: Date
    let statementDate: Date
    let dueDate: Date
    let currency: CurrencyCode
    let statementAmount: DecimalValue
    let minimumPayment: DecimalValue
    let paidAmount: DecimalValue
    let remainingAmount: DecimalValue
    let status: String
    let linkedCashFlowItemId: String?
    let note: String?
}

struct InstallmentPlanDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let linkedEntryId: String
    let creditAccountId: String
    let totalAmount: DecimalValue
    let currency: CurrencyCode
    let numberOfPayments: Int
    let paymentAmount: DecimalValue
    let feeAmount: DecimalValue
    let interestAmount: DecimalValue
    let startDate: Date
    let endDate: Date
    let status: String
    let generatedCashFlowCount: Int
    let note: String?
}

struct SubscriptionRuleDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let title: String
    let amount: DecimalValue
    let currency: CurrencyCode
    let accountId: String?
    let categoryId: String?
    let billingInterval: String
    let billingDay: Int?
    let startDate: Date
    let endDate: Date?
    let nextChargeDate: Date?
    let status: String
    let generatedCashFlowCount: Int
    let note: String?
}

struct AIConfigDTO: Decodable, Equatable, Hashable {
    let provider: String
    let model: String?
    let baseUrlConfigured: Bool
    let apiKeyConfigured: Bool
    let autoConfirmLimitCny: DecimalValue
}

struct AIPlanDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let sourceText: String
    let provider: String
    let model: String?
    let status: String
    let riskLevel: String
    let autoConfirmEligible: Bool
    let confidence: DecimalValue?
    let explanation: String?
    let rawResponse: [String: JSONValueDTO]?
    let actions: [AIActionDTO]
}

struct AIActionDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let planId: String
    let executionOrder: Int
    let actionType: String
    let status: String
    let riskLevel: String
    let requiresConfirmation: Bool
    let payload: [String: JSONValueDTO]
    let explanation: String?
    let result: [String: JSONValueDTO]?
    let rollbackPayload: [String: JSONValueDTO]?
    let targetType: String?
    let targetId: String?
    let errorMessage: String?
}

struct NotificationRuleDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let title: String
    let ruleType: String
    let channel: String
    let triggerPayload: [String: JSONValueDTO]
    let status: String
    let nextTriggerDate: Date?
    let lastTriggeredAt: Date?
    let note: String?
}

struct PushDeviceDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let deviceId: String
    let platform: String
    let apnsToken: String
    let appVersion: String?
    let installedAt: Date
    let lastSeenAt: Date
    let enabled: Bool
}

// MARK: - Auth (Sign in with Apple, v1.2)

struct AuthUserDTO: Decodable, Equatable {
    let id: String
    let appleUserId: String
    let email: String?
    let emailVerified: Bool
    let displayName: String?
    let isAdmin: Bool
}

struct AuthSessionDTO: Decodable, Identifiable, Equatable {
    let id: String
    let deviceLabel: String
    let platform: String
    let appVersion: String?
    let issuedAt: Date
    let lastSeenAt: Date
    let expiresAt: Date
    var isCurrent: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, deviceLabel, platform, appVersion, issuedAt, lastSeenAt, expiresAt, isCurrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        deviceLabel = try container.decode(String.self, forKey: .deviceLabel)
        platform = try container.decode(String.self, forKey: .platform)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        issuedAt = try container.decode(Date.self, forKey: .issuedAt)
        lastSeenAt = try container.decode(Date.self, forKey: .lastSeenAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
    }
}

struct AppleSignInResponseDTO: Decodable {
    let sessionToken: String
    let expiresAt: Date
    let user: AuthUserDTO
}

struct AuthMeResponseDTO: Decodable {
    let user: AuthUserDTO?
    let session: AuthSessionDTO?
    let admin: Bool?
}

struct AuthSessionListResponseDTO: Decodable {
    let items: [AuthSessionDTO]
}

struct AuditLogDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let actor: String
    let actionType: String
    let targetType: String
    let targetId: String
    let beforeSnapshot: [String: JSONValueDTO]?
    let afterSnapshot: [String: JSONValueDTO]?
    let note: String?
}

struct AIMemoDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let periodStart: Date
    let periodEnd: Date
    let summary: String
    let statsJson: [String: JSONValueDTO]
    let promptToken: Int
    let completionToken: Int
    let generator: String
    let status: String
    let confidence: DecimalValue
    let createdAt: Date
    let updatedAt: Date
}

struct AIMemoListResponseDTO: Decodable, Equatable, Hashable {
    let items: [AIMemoDTO]
}

struct ReconciliationAccountDTO: Identifiable, Decodable, Equatable, Hashable {
    var id: String { accountId }
    let accountId: String
    let accountName: String
    let accountType: AccountType
    let currency: CurrencyCode
    let expectedAmount: DecimalValue
    let currentAmount: DecimalValue
    let deltaAmount: DecimalValue
    let needsAdjustment: Bool
}

struct ReconciliationAccountsResponseDTO: Decodable, Equatable, Hashable {
    let threshold: DecimalValue
    let items: [ReconciliationAccountDTO]
}

struct AccountAdjustmentDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let accountId: String
    let reason: String
    let deltaAmount: DecimalValue
    let currency: CurrencyCode
    let balanceBefore: DecimalValue
    let balanceAfter: DecimalValue
    let source: String
    let note: String?
    let createdBy: String
}

// --- v2.2.0 P3 · 对账一致性/冲突检测器 (GET /reconciliation/check) -----------
//
// The new reconciliation surface (replaces the misleading "系统余额 vs 当前余额"
// pair, which were two internal恒等数). The detector returns per-account conflicts
// plus a top-level orphan list. Each conflict carries a `fix` telling the UI which
// correction路径 to offer (重算 / 跳转记录 / 录真实数).

/// How the UI should let the user correct a conflict.
enum ReconciliationFix: String, Decodable, Hashable {
    /// R1 信用欠款漂移 → 调 POST /reconciliation/recompute-credit/{id} 重算对平.
    case internalRecompute = "internal_recompute"
    /// R2/R4 → 跳转到 offending 记录（账单周期 / 还款现金流 / 报销）让用户改/补.
    case jumpRecord = "jump_record"
    /// R3 余额↔真实 → 录真实余额 → POST /reconciliation/adjustments 对平.
    case externalActual = "external_actual"
    /// 仅展示拆解，无需纠错.
    case none

    /// Unknown future fix codes degrade to `.none` (never break decoding).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReconciliationFix(rawValue: raw) ?? .none
    }
}

/// A jump-to pointer at the offending record (前端导航用).
struct ReconciliationPointerDTO: Decodable, Equatable, Hashable, Identifiable {
    /// credit_statement_cycle | cash_flow_item | reimbursement_claim | account
    let type: String
    let id: String
    let label: String
}

struct ReconciliationConflictDTO: Decodable, Equatable, Hashable, Identifiable {
    /// credit_three_way | statement_cashflow | balance_external | orphan
    let code: String
    /// conflict（红） | info（仅展示拆解）
    let severity: String
    let title: String
    // R1 信用三数拆解（仅 credit_three_way 填）.
    let storedLiability: DecimalValue?
    let sumOpenStatements: DecimalValue?
    let unbilledCharges: DecimalValue?
    let expectedLiability: DecimalValue?
    // R3 余额外部真相（仅 balance_external 填）.
    let storedBalance: DecimalValue?
    let externalActual: DecimalValue?
    // stored − expected（R1） / stored − external_actual（R3）.
    let delta: DecimalValue?
    // 该 delta 的币种（外币卡按此渲染符号，nil 时回退 .cny）.
    let currency: CurrencyCode?
    let detail: String?
    let offending: [ReconciliationPointerDTO]
    let fix: ReconciliationFix

    // Conflicts have no server id; identify by the value content (stable within a
    // single check snapshot).
    var id: String { "\(code)|\(title)|\(offending.map(\.id).joined(separator: ","))" }

    var isConflict: Bool { severity == "conflict" }
}

/// R1 三数拆解（界面三数展示用，仅信用账户填）.
struct ReconciliationBreakdownDTO: Decodable, Equatable, Hashable {
    let storedLiability: DecimalValue
    let openStatementsTotal: DecimalValue
    let unbilledCharges: DecimalValue
}

struct ReconciliationCheckAccountDTO: Decodable, Equatable, Hashable, Identifiable {
    let accountId: String
    let accountName: String
    let accountType: AccountType
    let currency: CurrencyCode
    let hasConflicts: Bool
    let conflicts: [ReconciliationConflictDTO]
    let breakdown: ReconciliationBreakdownDTO?

    var id: String { accountId }
}

struct ReconciliationCheckResponseDTO: Decodable, Equatable, Hashable {
    let checkedAt: Date
    let hasConflicts: Bool
    let accounts: [ReconciliationCheckAccountDTO]
    /// R4 孤儿/状态一致性 — 不绑某一账户的全局孤儿（现金流 / 报销 / 周期）.
    let orphans: [ReconciliationConflictDTO]
}

struct CreditRecomputeResponseDTO: Decodable, Equatable, Hashable {
    let accountId: String
    let accountName: String
    let storedLiabilityBefore: DecimalValue
    let recomputedLiability: DecimalValue
    let delta: DecimalValue
    let adjustmentId: String?
}

struct DailyPnLReadDTO: Decodable, Equatable, Hashable {
    let adjustmentId: String
    let accountId: String
    let currency: CurrencyCode
    let balanceBefore: DecimalValue
    let balanceAfter: DecimalValue
    let deltaAmount: DecimalValue
    let asOfDate: Date
    let source: String
}

struct SearchHitDTO: Identifiable, Decodable, Equatable, Hashable {
    let type: String
    let id: String
    let title: String
    let subtitle: String?
    let relevance: Double
    let target: String
    let metadata: [String: JSONValueDTO]
}

struct SearchResponseDTO: Decodable, Equatable, Hashable {
    let query: String
    let limit: Int
    let items: [SearchHitDTO]
}

struct CurrencyAmountSummaryDTO: Decodable, Equatable, Hashable {
    let currency: CurrencyCode
    let amount: DecimalValue
    let convertedCnyAmount: DecimalValue
}

struct MonthlyOverviewReportDTO: Decodable, Equatable, Hashable {
    let dateFrom: Date
    let dateTo: Date
    let baseCurrency: String
    let incomeCny: DecimalValue
    let expenseCny: DecimalValue
    let netIncomeCny: DecimalValue
    let expectedReimbursementCny: DecimalValue
    let approvedReimbursementCny: DecimalValue
    let receivedReimbursementCny: DecimalValue
    let personalNetExpenseCny: DecimalValue
    let futureInflowCny: DecimalValue
    let futureOutflowCny: DecimalValue
    let futureNetCny: DecimalValue
    let creditLiabilityCny: DecimalValue
}

struct CategoryExpenseRowDTO: Identifiable, Decodable, Equatable, Hashable {
    var id: String { categoryId }
    let categoryId: String
    let categoryName: String
    let expenseCny: DecimalValue
    let currencies: [CurrencyAmountSummaryDTO]
}

struct CategoryExpenseReportDTO: Decodable, Equatable, Hashable {
    let dateFrom: Date
    let dateTo: Date
    let baseCurrency: String
    let totalExpenseCny: DecimalValue
    let rows: [CategoryExpenseRowDTO]
}

struct CashFlowPressureWindowDTO: Identifiable, Decodable, Equatable, Hashable {
    var id: Int { days }
    let days: Int
    let dateFrom: Date
    let dateTo: Date
    let expectedInflowCny: DecimalValue
    let expectedOutflowCny: DecimalValue
    let netCny: DecimalValue
    let itemCount: Int
}

struct CashFlowDailyNetRowDTO: Identifiable, Decodable, Equatable, Hashable {
    var id: Date { date }
    let date: Date
    let inflowCny: DecimalValue
    let outflowCny: DecimalValue
    let netCny: DecimalValue
}

struct CashFlowPressureReportDTO: Decodable, Equatable, Hashable {
    let anchorDate: Date
    let baseCurrency: String
    let windows: [CashFlowPressureWindowDTO]
    let dailyNetCny: [CashFlowDailyNetRowDTO]?
}

struct CreditLiabilityTrendRowDTO: Identifiable, Decodable, Equatable, Hashable {
    var id: String { cycleId }
    let cycleId: String
    let creditAccountId: String
    let accountName: String
    let statementDate: Date
    let dueDate: Date
    let currency: CurrencyCode
    let statementAmount: DecimalValue
    let paidAmount: DecimalValue
    let remainingAmount: DecimalValue
    let remainingCny: DecimalValue
    let status: String
}

struct CreditLiabilityTrendReportDTO: Decodable, Equatable, Hashable {
    let dateFrom: Date
    let dateTo: Date
    let baseCurrency: String
    let totalRemainingCny: DecimalValue
    let rows: [CreditLiabilityTrendRowDTO]
}

struct ReimbursementStatusSummaryDTO: Identifiable, Decodable, Equatable, Hashable {
    var id: String { status }
    let status: String
    let amountCny: DecimalValue
    let claimCount: Int
}

struct ReimbursementReportDTO: Decodable, Equatable, Hashable {
    let dateFrom: Date
    let dateTo: Date
    let view: String
    let baseCurrency: String
    let grossReimbursableExpenseCny: DecimalValue
    let expectedOffsetCny: DecimalValue
    let approvedOffsetCny: DecimalValue
    let receivedOffsetCny: DecimalValue
    let preReimbursementExpenseCny: DecimalValue
    let expectedNetExpenseCny: DecimalValue
    let approvedNetExpenseCny: DecimalValue
    let receivedNetExpenseCny: DecimalValue
    let personalNetExpenseCny: DecimalValue
    let selectedNetExpenseCny: DecimalValue
    let statusBreakdown: [ReimbursementStatusSummaryDTO]
    let currencies: [CurrencyAmountSummaryDTO]
}

struct SubscriptionReportDTO: Decodable, Equatable, Hashable {
    let asOf: Date
    let baseCurrency: String
    let activeSubscriptionCount: Int
    let monthlyTotalCny: DecimalValue
    let annualTotalCny: DecimalValue
    let upcoming30DaysCny: DecimalValue
    let currencies: [CurrencyAmountSummaryDTO]
}

struct ExportDatasetDTO: Identifiable, Decodable, Equatable, Hashable {
    var id: String { name }
    let name: String
    let filename: String
}

struct ExportDatasetListDTO: Decodable, Equatable, Hashable {
    let datasets: [ExportDatasetDTO]
}

enum AccountType: String, Codable, CaseIterable, Hashable {
    case balance
    case credit
    case investment

    var title: String {
        switch self {
        case .balance: "余额"
        case .credit: "信用"
        case .investment: "投资"
        }
    }
}

enum CategoryType: String, Codable, CaseIterable, Hashable {
    case expense
    case income
    case transfer
    case system

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        case .system: "系统"
        }
    }
}

enum CategoryDirection: String, Codable, Hashable {
    case expense
    case income

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        }
    }
}

enum EntryStatus: String, Codable, CaseIterable, Hashable {
    case draft
    case confirmed
    case voided

    var title: String {
        switch self {
        case .draft: "草稿"
        case .confirmed: "已确认"
        case .voided: "已作废"
        }
    }
}

enum MovementType: String, Codable, Hashable {
    case balanceIn = "balance_in"
    case balanceOut = "balance_out"
    case creditCharge = "credit_charge"
    case creditRepayment = "credit_repayment"
    case transferIn = "transfer_in"
    case transferOut = "transfer_out"
}

enum CurrencyCode: String, Codable, CaseIterable, Hashable {
    case cny = "CNY"
    case usd = "USD"

    var symbol: String {
        switch self {
        case .cny: "¥"
        case .usd: "$"
        }
    }
}

#if canImport(AppIntents)
extension CurrencyCode: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "币种")
    }

    static var caseDisplayRepresentations: [CurrencyCode: DisplayRepresentation] {
        [
            .cny: DisplayRepresentation(title: "人民币"),
            .usd: DisplayRepresentation(title: "美元"),
        ]
    }
}
#endif

struct DecimalValue: Codable, Equatable, Hashable, Comparable {
    let value: Decimal

    init(_ value: Decimal) {
        self.value = value
    }

    init(_ intValue: Int) {
        self.value = Decimal(intValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self), let decimal = Decimal(string: text) {
            value = decimal
            return
        }
        if let int = try? container.decode(Int.self) {
            value = Decimal(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            value = Decimal(double)
            return
        }
        throw DecodingError.typeMismatch(
            Decimal.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected decimal string or number")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).stringValue)
    }

    static func < (lhs: DecimalValue, rhs: DecimalValue) -> Bool {
        lhs.value < rhs.value
    }
}

enum JSONValueDTO: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValueDTO])
    case array([JSONValueDTO])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValueDTO].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValueDTO].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var displayText: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            "\(value)"
        case .bool(let value):
            value ? "true" : "false"
        case .object(let value):
            value.isEmpty ? "{}" : value.keys.sorted().joined(separator: ", ")
        case .array(let value):
            "\(value.count) 项"
        case .null:
            "null"
        }
    }
}

extension String {
    var financeStatusTitle: String {
        switch self {
        case "expected": "预计"
        case "confirmed": "已确认"
        case "settled": "已结算"
        case "cancelled", "canceled": "已取消"
        case "reimbursable": "可报销"
        case "invoice_pending": "待发票"
        case "submitted": "已提交"
        case "approved": "已批准"
        case "waiting_received": "待到账"
        case "received": "已到账"
        case "partial_received": "部分到账"
        case "rejected": "已拒绝"
        case "abandoned": "已放弃"
        case "open": "未出账"
        case "statement_generated": "已出账"
        case "partially_paid": "部分还款"
        case "paid": "已还清"
        case "overdue": "已逾期"
        case "closed": "已关闭"
        case "active": "启用"
        case "paused": "暂停"
        case "auto_confirm_candidate": "可自动确认"
        case "requires_confirmation": "待确认"
        case "executed": "已执行"
        case "failed": "失败"
        case "rolled_back": "已回滚"
        case "pending": "待处理"
        case "published": "已发布"
        case "archived": "已归档"
        case "account_adjustment.create": "账户对账调整"
        case "low": "低风险"
        case "medium": "中风险"
        case "high": "高风险"
        case "inflow": "进账"
        case "outflow": "出账"
        case "transfer": "转账"
        case "salary": "工资"
        case "rent_income": "租金收入"
        case "reimbursement": "报销"
        case "subscription": "订阅"
        case "credit_repayment": "信用还款"
        case "installment": "分期"
        case "one_time": "一次性"
        case "other": "其他"
        case "weekly": "每周"
        case "monthly": "每月"
        case "yearly": "每年"
        case "cash_flow": "现金流"
        case "anomaly": "异常"
        case "in_app": "应用内"
        case "system": "系统"
        case "email": "邮件"
        default: replacingOccurrences(of: "_", with: " ")
        }
    }
}
