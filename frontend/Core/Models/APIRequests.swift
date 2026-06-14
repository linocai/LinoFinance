import Foundation

struct AccountCreateRequest: Encodable {
    var name: String
    var type: AccountType
    var currency: CurrencyCode
    var currentBalance: DecimalValue
    var currentLiability: DecimalValue = DecimalValue(0)
    var includeInNetWorth = true
    var status = "active"
    var displayOrder = 0
    var creditLimit: DecimalValue?
    var statementDay: Int?
    var dueDay: Int?
    var minimumPayment: DecimalValue?
    var notes: String?
}

/// PATCH /accounts/{id} — editable safe subset only. The backend schema is
/// `extra="forbid"`: `type` / `currency` / `current_balance` / `current_liability`
/// are immutable and MUST NOT be sent (balance changes flow through reconciliation).
/// nil fields are omitted (left unchanged).
struct AccountUpdateRequest: Encodable {
    var name: String?
    var includeInNetWorth: Bool?
    var status: String?
    var displayOrder: Int?
    var creditLimit: DecimalValue?
    var statementDay: Int?
    var dueDay: Int?
    var minimumPayment: DecimalValue?
    var notes: String?
}

struct CategoryCreateRequest: Encodable {
    var name: String
    var type: CategoryType
    var parentId: String?
    var isActive = true
    var displayOrder = 0
}

/// PATCH /categories/{id} — editable subset (`extra="forbid"`: type / parent_id
/// immutable). nil fields omitted.
struct CategoryUpdateRequest: Encodable {
    var name: String?
    var isActive: Bool?
    var displayOrder: Int?
}

struct CurrencyRateCreateRequest: Encodable {
    var fromCurrency: CurrencyCode
    var toCurrency: CurrencyCode = .cny
    var rate: DecimalValue
    var date: Date
    var source = "manual"
    var note: String?
}

/// PATCH /currency-rates/{id} — only `rate` is editable (`extra="forbid"`:
/// from/to/date immutable); rejected with 409 if the rate is already referenced.
struct CurrencyRateUpdateRequest: Encodable {
    var rate: DecimalValue
}

struct EntryCreateRequest: Encodable {
    var title: String
    var entryType = "single"
    var date: Date
    var startDate: Date?
    var endDate: Date?
    var status: EntryStatus
    var note: String?
    var createdBy = "user"
    var categoryLines: [EntryCategoryLineCreateRequest]
    var accountMovements: [AccountMovementCreateRequest]
}

struct EntryCategoryLineCreateRequest: Encodable {
    var categoryId: String
    var direction: CategoryDirection
    var amount: DecimalValue
    var currency: CurrencyCode
    var exchangeRateId: String?
    var convertedCnyAmount: DecimalValue?
    var reimbursableFlag = false
    var reimbursementPayer: String?
    var reimbursementExpectedDate: Date?
    var reimbursementStatus: String?
    var note: String?
}

struct AccountMovementCreateRequest: Encodable {
    var accountId: String
    var statementCycleId: String?
    var movementType: MovementType
    var amount: DecimalValue
    var currency: CurrencyCode
    var exchangeRateId: String?
    var convertedCnyAmount: DecimalValue?
    var note: String?
}

struct CashFlowItemCreateRequest: Encodable {
    var title: String
    var direction: String
    var cashFlowType: String
    var amount: DecimalValue
    var currency: CurrencyCode
    var exchangeRateId: String?
    var convertedCnyAmount: DecimalValue?
    var expectedDate: Date
    var accountId: String?
    var categoryId: String?
    var recurrenceRule: String?
    var status = "expected"
    var linkedReimbursementId: String?
    var linkedInstallmentPlanId: String?
    var linkedSubscriptionRuleId: String?
    var linkedStatementCycleId: String?
    var note: String?
}

/// Wrapper that lets a JSON encoder emit `null` for an explicit clear while
/// the outer Optional still elides the field when it's truly absent.
///
/// PATCH endpoints (v1.1.7+) rely on this to tell "leave unchanged" apart
/// from "unlink": pass `nil` (the outer Optional) to skip the field, or
/// `.null` to send JSON `null` so the backend treats the column as cleared.
enum Nullable<T: Encodable>: Encodable {
    case value(T)
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct CashFlowItemUpdateRequest: Encodable {
    var title: String?
    var direction: String?
    var cashFlowType: String?
    var amount: DecimalValue?
    var currency: CurrencyCode?
    var exchangeRateId: String?
    var convertedCnyAmount: DecimalValue?
    var expectedDate: Date?
    /// Use `.value(id)` to link, `.null` to unlink, omit entirely to leave alone.
    var accountId: Nullable<String>?
    /// Use `.value(id)` to link, `.null` to unlink, omit entirely to leave alone.
    var categoryId: Nullable<String>?
    var recurrenceRule: String?
    var note: String?
}

struct CashFlowSettleRequest: Encodable {
    var entry: EntryCreateRequest
}

struct ReimbursementClaimCreateRequest: Encodable {
    var linkedEntryId: String
    var linkedEntryLineId: String?
    var amount: DecimalValue
    var currency: CurrencyCode
    var exchangeRateId: String?
    var convertedCnyAmount: DecimalValue?
    var payer = "company"
    var expectedDate: Date
    var status = "reimbursable"
    var invoiceAttachmentIds: [String]?
    var note: String?
}

struct ReimbursementReceiveRequest: Encodable {
    var actualReceivedDate: Date
    var receivedAccountId: String
    var entry: EntryCreateRequest
}

struct CreditStatementCycleCreateRequest: Encodable {
    var creditAccountId: String
    var cycleStartDate: Date
    var cycleEndDate: Date
    var statementDate: Date
    var dueDate: Date
    var currency: CurrencyCode
    var statementAmount: DecimalValue = DecimalValue(0)
    var minimumPayment: DecimalValue = DecimalValue(0)
    var paidAmount: DecimalValue = DecimalValue(0)
    var status = "open"
    var linkedCashFlowItemId: String?
    var note: String?
}

struct InstallmentPlanCreateRequest: Encodable {
    var linkedEntryId: String
    var creditAccountId: String
    var totalAmount: DecimalValue
    var currency: CurrencyCode
    var numberOfPayments: Int
    var paymentAmount: DecimalValue?
    var feeAmount: DecimalValue = DecimalValue(0)
    var interestAmount: DecimalValue = DecimalValue(0)
    var startDate: Date
    var status = "active"
    var note: String?
}

struct SubscriptionRuleCreateRequest: Encodable {
    var title: String
    var amount: DecimalValue
    var currency: CurrencyCode
    var accountId: String?
    var categoryId: String?
    var billingInterval: String
    var billingDay: Int?
    var startDate: Date
    var endDate: Date?
    var nextChargeDate: Date?
    var status = "active"
    var note: String?
}

struct AIActionProposalRequest: Encodable {
    var actionType: String
    var payload: [String: JSONValueDTO]
    var explanation: String?
    var confidence: DecimalValue?
}

struct AIPlanCreateRequest: Encodable {
    var sourceText: String
    var actions: [AIActionProposalRequest] = []
    var explanation: String?
    var confidence: DecimalValue?
    var rawResponse: [String: JSONValueDTO]?
}

struct AINoteRequest: Encodable {
    var note: String?
}

struct AIExecuteRequest: Encodable {
    var strongConfirm: String?
}

struct AIMemoGenerateRequest: Encodable {
    var periodStart: Date
    var periodEnd: Date
    var status = "draft"
}

struct AIMemoPatchRequest: Encodable {
    var summary: String?
    var status: String?
}

struct AccountAdjustmentCreateRequest: Encodable {
    var accountId: String
    var actualAmount: DecimalValue?
    var reason: String
    var note: String?
    var createdBy = "user"
}

struct DailyPnLCreateRequest: Encodable {
    var newBalance: DecimalValue
    var asOfDate: Date?
    var note: String?
}

struct NotificationRuleCreateRequest: Encodable {
    var title: String
    var ruleType: String
    var channel = "in_app"
    var triggerPayload: [String: JSONValueDTO] = [:]
    var status = "active"
    var nextTriggerDate: Date?
    var note: String?
}

struct PushDeviceRegisterRequest: Encodable {
    var deviceId: String
    var platform: String
    var apnsToken: String
    var appVersion: String?
}

struct AppleSignInRequest: Encodable {
    var identityToken: String
    var deviceLabel: String
    var platform: String           // "ios" | "macos"
    var appVersion: String?
    var firstName: String?
    var lastName: String?
}
