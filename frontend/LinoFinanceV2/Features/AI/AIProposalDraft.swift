import Foundation

// AIProposalDraft — v3.0.0 P4 ① 提案明细的本地可编辑草稿 (id 映射安全网核心).
//
// `POST /ai/plans` returns each action's `payload` as a server-opaque
// `[String: JSONValueDTO]` (backend `Dict[str, Any]`, no fixed Codable shape).
// This file parses that payload into a typed, picker-editable draft for the two
// action types that move money against an account/category — `CreateEntry` and
// `RecordCreditRepayment` (both EntryCreate-shaped; RecordCreditRepayment's
// payload may additionally be wrapped as `{"entry": {...}}`, see `_apply_action`
// in `backend/app/services/ai.py`) — and `CreateCashFlowItem`. Every other
// action type (MarkReimbursable / SetCashFlowStatus / UpdateReimbursementStatus /
// GenerateNotificationRule / CreateInstallmentPlan / anything future) falls back
// to `.passthrough`: still listed (每个提案列出全部 actions) and resent
// byte-for-byte unedited, just without a dedicated editor — those shapes don't
// carry a bare account_id/category_id the way CreateEntry does, so there is no
// id-mapping gap to plug for them in this version.
//
// Rebuilding a payload from an edited draft reuses the SAME `Encodable` request
// types (`EntryCreateRequest` etc.) + JSON settings (`.convertToSnakeCase` +
// `linoAPIDate`) the rest of the app already POSTs with — encode then re-decode
// into `[String: JSONValueDTO]` — instead of hand-rolling key strings, so the
// wire shape can never drift from what `POST /entries` / `POST /cash-flow-items`
// already validate.
//
// Two-layer validation: `EditableEntryDraft`/`EditableCashFlowDraft.toRequest()`
// only check STRUCTURAL completeness (an id is present, the amount parses) —
// they have no account/category list to check against. The id ALSO has to
// resolve to something in the user's CURRENT active accounts/categories — that
// SEMANTIC check lives in `validationError(accounts:categories:)`, called by
// `AIAssistantModel` before it ever attempts to build a request. This catches
// both "AI left it blank" and "the account/category was deleted since this
// plan was created" the same way (both show as an unresolved picker).

enum AIProposalDraftError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

enum AIProposalActionKind {
    case entry(EditableEntryDraft, wrapped: Bool)
    case cashFlowItem(EditableCashFlowDraft)
    case voidEntry(entryId: String?, rawPayload: [String: JSONValueDTO])
    case passthrough([String: JSONValueDTO])

    static func title(for actionType: String) -> String {
        switch actionType {
        case "CreateEntry": "记一笔"
        case "CreateCashFlowItem": "计划收支"
        case "MarkReimbursable": "标记可报销"
        case "CreateInstallmentPlan": "创建分期"
        case "RecordCreditRepayment": "信用卡还款"
        case "GenerateNotificationRule": "创建提醒"
        case "SetCashFlowStatus": "调整现金流状态"
        case "UpdateReimbursementStatus": "调整报销状态"
        case "VoidEntry": "撤销记录"
        default: actionType
        }
    }
}

struct EditableAIAction: Identifiable {
    /// The server action id when parsed from an existing `AIActionDTO` (stable
    /// across edits — used only as a SwiftUI list identity, never re-sent).
    let id: String
    let actionType: String
    let explanation: String?
    /// Risk level as LAST known from the server — display only. The
    /// authoritative value is always recomputed server-side when the edited
    /// actions are resubmitted (`AIAssistantModel.prepareExecution`).
    let riskLevel: String
    var kind: AIProposalActionKind

    init(action: AIActionDTO) {
        self.id = action.id
        self.actionType = action.actionType
        self.explanation = action.explanation
        self.riskLevel = action.riskLevel
        self.kind = Self.parseKind(actionType: action.actionType, payload: action.payload)
    }

    var typeTitle: String { AIProposalActionKind.title(for: actionType) }
    var isHighRisk: Bool { riskLevel == "high" }

    func validationError(accounts: [AccountDTO], categories: [CategoryDTO]) -> String? {
        switch kind {
        case .entry(let draft, _):
            return draft.validationError(accounts: accounts, categories: categories)
        case .cashFlowItem(let draft):
            return draft.validationError(accounts: accounts, categories: categories)
        case .voidEntry, .passthrough:
            return nil
        }
    }

    func toProposalRequest() throws -> AIActionProposalRequest {
        let payload: [String: JSONValueDTO]
        switch kind {
        case .entry(let draft, let wrapped):
            let encoded = try AIProposalPayloadCoding.encode(try draft.toRequest())
            payload = wrapped ? ["entry": .object(encoded)] : encoded
        case .cashFlowItem(let draft):
            payload = try AIProposalPayloadCoding.encode(try draft.toRequest())
        case .voidEntry(_, let raw):
            payload = raw
        case .passthrough(let raw):
            payload = raw
        }
        return AIActionProposalRequest(actionType: actionType, payload: payload, explanation: explanation, confidence: nil)
    }

    private static func parseKind(actionType: String, payload: [String: JSONValueDTO]) -> AIProposalActionKind {
        switch actionType {
        case "CreateEntry":
            return .entry(EditableEntryDraft.parse(payload), wrapped: false)
        case "RecordCreditRepayment":
            if let wrapped = JSONPayload.object(payload["entry"]) {
                return .entry(EditableEntryDraft.parse(wrapped), wrapped: true)
            }
            return .entry(EditableEntryDraft.parse(payload), wrapped: false)
        case "CreateCashFlowItem":
            return .cashFlowItem(EditableCashFlowDraft.parse(payload))
        case "VoidEntry":
            return .voidEntry(entryId: JSONPayload.string(payload, "entry_id"), rawPayload: payload)
        default:
            return .passthrough(payload)
        }
    }
}

// MARK: - CreateEntry / RecordCreditRepayment

struct EditableEntryDraft {
    var title: String
    var entryType: String
    var date: Date
    var note: String?
    var categoryLines: [EditableCategoryLine]
    var accountMovements: [EditableAccountMovement]

    /// Mirrors backend `_is_transfer_only`: an entry whose movements are all
    /// transfer-family (transfer_in / transfer_out / credit_repayment) needs no
    /// category lines; anything else does (`_validate_confirmable`).
    var isTransferOnly: Bool {
        !accountMovements.isEmpty && accountMovements.allSatisfy {
            [.transferIn, .transferOut, .creditRepayment].contains($0.movementType)
        }
    }

    func validationError(accounts: [AccountDTO], categories: [CategoryDTO]) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写标题" }
        // Structural completeness first — mirrors backend `_validate_confirmable`
        // (real-device 2026-07-11: an LLM proposal with movements but ZERO
        // category lines sailed past the old both-empty check, auto-executed,
        // and died on the server's 400 with the plan stuck in terminal failed).
        if accountMovements.isEmpty { return "缺少账户流水行，无法提交" }
        if categoryLines.isEmpty && !isTransferOnly { return "缺少分类行，请补充分类" }
        for line in categoryLines {
            guard let categoryId = line.categoryId, categories.contains(where: { $0.id == categoryId }) else {
                return "有一行分类还没选（或原分类已不可用）"
            }
            guard let amount = parseDecimalAmount(line.amountText), amount > 0 else { return "有一行金额无效" }
        }
        for movement in accountMovements {
            guard let accountId = movement.accountId, accounts.contains(where: { $0.id == accountId }) else {
                return "有一笔账户流水还没选账户（或原账户已不可用）"
            }
            guard let amount = parseDecimalAmount(movement.amountText), amount > 0 else { return "有一笔账户流水金额无效" }
        }
        return nil
    }

    func toRequest() throws -> EntryCreateRequest {
        let lines = try categoryLines.map { try $0.toRequest() }
        let movements = try accountMovements.map { try $0.toRequest() }
        guard !lines.isEmpty || !movements.isEmpty else {
            throw AIProposalDraftError.message("没有可提交的记账内容")
        }
        return EntryCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            entryType: entryType,
            date: date,
            status: .confirmed,
            note: note,
            categoryLines: lines,
            accountMovements: movements
        )
    }

    static func parse(_ payload: [String: JSONValueDTO]) -> EditableEntryDraft {
        var draft = EditableEntryDraft(
            title: JSONPayload.string(payload, "title") ?? "",
            entryType: JSONPayload.string(payload, "entry_type") ?? "single",
            date: JSONPayload.date(payload, "date") ?? Date(),
            note: JSONPayload.string(payload, "note"),
            categoryLines: JSONPayload.array(payload, "category_lines").compactMap {
                JSONPayload.object($0).map(EditableCategoryLine.parse)
            },
            accountMovements: JSONPayload.array(payload, "account_movements").compactMap {
                JSONPayload.object($0).map(EditableAccountMovement.parse)
            }
        )
        draft.synthesizeMissingCategoryLine()
        return draft
    }

    /// LLM proposals may legally omit category lines when no listed category
    /// fits (the prompt says "leave blank and explain"). A non-transfer entry
    /// without lines can never be confirmed server-side, and the review UI has
    /// no add-row affordance — so synthesize ONE blank line mirroring the
    /// movements' total (amount/currency/direction) for the user to pick a
    /// category into. `categoryId` stays nil, so `validationError` blocks both
    /// the intent auto-execute veto and the in-app confirm until it's chosen.
    private mutating func synthesizeMissingCategoryLine() {
        guard categoryLines.isEmpty, !accountMovements.isEmpty, !isTransferOnly else { return }
        let spending = accountMovements.filter { [.balanceOut, .creditCharge].contains($0.movementType) }
        let income = accountMovements.filter { $0.movementType == .balanceIn }
        let source = spending.isEmpty ? income : spending
        guard let first = source.first else { return }
        let sameCurrency = source.filter { $0.currency == first.currency }
        let total = sameCurrency
            .compactMap { parseDecimalAmount($0.amountText) }
            .reduce(Decimal(0), +)
        categoryLines = [EditableCategoryLine(
            categoryId: nil,
            direction: spending.isEmpty ? .income : .expense,
            amountText: total > 0 ? NSDecimalNumber(decimal: total).stringValue : first.amountText,
            currency: first.currency,
            exchangeRateId: nil,
            convertedCnyAmountText: nil,
            reimbursableFlag: false,
            reimbursementPayer: nil,
            reimbursementExpectedDate: nil,
            reimbursementStatus: nil
        )]
    }
}

struct EditableCategoryLine: Identifiable {
    let id = UUID()
    var categoryId: String?
    var direction: CategoryDirection
    var amountText: String
    var currency: CurrencyCode
    // Passthrough extras — not surfaced in the review UI, preserved verbatim.
    var exchangeRateId: String?
    var convertedCnyAmountText: String?
    var reimbursableFlag: Bool
    var reimbursementPayer: String?
    var reimbursementExpectedDate: Date?
    var reimbursementStatus: String?
    var note: String?

    func toRequest() throws -> EntryCategoryLineCreateRequest {
        guard let categoryId, let amount = parseDecimalAmount(amountText), amount > 0 else {
            throw AIProposalDraftError.message("有一行分类或金额未填写完整")
        }
        return EntryCategoryLineCreateRequest(
            categoryId: categoryId,
            direction: direction,
            amount: DecimalValue(amount),
            currency: currency,
            exchangeRateId: exchangeRateId,
            convertedCnyAmount: convertedCnyAmountText.flatMap(parseDecimalAmount).map(DecimalValue.init),
            reimbursableFlag: reimbursableFlag,
            reimbursementPayer: reimbursementPayer,
            reimbursementExpectedDate: reimbursementExpectedDate,
            reimbursementStatus: reimbursementStatus,
            note: note
        )
    }

    static func parse(_ dict: [String: JSONValueDTO]) -> EditableCategoryLine {
        EditableCategoryLine(
            categoryId: JSONPayload.string(dict, "category_id"),
            direction: CategoryDirection(rawValue: JSONPayload.string(dict, "direction") ?? "expense") ?? .expense,
            amountText: JSONPayload.amountText(dict, "amount"),
            currency: CurrencyCode(rawValue: (JSONPayload.string(dict, "currency") ?? "CNY").uppercased()) ?? .cny,
            exchangeRateId: JSONPayload.string(dict, "exchange_rate_id"),
            convertedCnyAmountText: JSONPayload.optionalAmountText(dict, "converted_cny_amount"),
            reimbursableFlag: JSONPayload.bool(dict, "reimbursable_flag"),
            reimbursementPayer: JSONPayload.string(dict, "reimbursement_payer"),
            reimbursementExpectedDate: JSONPayload.date(dict, "reimbursement_expected_date"),
            reimbursementStatus: JSONPayload.string(dict, "reimbursement_status"),
            note: JSONPayload.string(dict, "note")
        )
    }
}

struct EditableAccountMovement: Identifiable {
    let id = UUID()
    var accountId: String?
    var movementType: MovementType
    var amountText: String
    var currency: CurrencyCode
    // Passthrough extras — preserved verbatim, no dedicated editor.
    var statementCycleId: String?
    var exchangeRateId: String?
    var convertedCnyAmountText: String?
    var note: String?

    func toRequest() throws -> AccountMovementCreateRequest {
        guard let accountId, let amount = parseDecimalAmount(amountText), amount > 0 else {
            throw AIProposalDraftError.message("有一笔账户流水未填写完整")
        }
        return AccountMovementCreateRequest(
            accountId: accountId,
            statementCycleId: statementCycleId,
            movementType: movementType,
            amount: DecimalValue(amount),
            currency: currency,
            exchangeRateId: exchangeRateId,
            convertedCnyAmount: convertedCnyAmountText.flatMap(parseDecimalAmount).map(DecimalValue.init),
            note: note
        )
    }

    static func parse(_ dict: [String: JSONValueDTO]) -> EditableAccountMovement {
        EditableAccountMovement(
            accountId: JSONPayload.string(dict, "account_id"),
            movementType: MovementType(rawValue: JSONPayload.string(dict, "movement_type") ?? "balance_out") ?? .balanceOut,
            amountText: JSONPayload.amountText(dict, "amount"),
            currency: CurrencyCode(rawValue: (JSONPayload.string(dict, "currency") ?? "CNY").uppercased()) ?? .cny,
            statementCycleId: JSONPayload.string(dict, "statement_cycle_id"),
            exchangeRateId: JSONPayload.string(dict, "exchange_rate_id"),
            convertedCnyAmountText: JSONPayload.optionalAmountText(dict, "converted_cny_amount"),
            note: JSONPayload.string(dict, "note")
        )
    }
}

// MARK: - CreateCashFlowItem

struct EditableCashFlowDraft {
    var title: String
    var direction: String
    var cashFlowType: String
    var amountText: String
    var currency: CurrencyCode
    var expectedDate: Date
    var accountId: String?
    var categoryId: String?
    // Passthrough extras.
    var exchangeRateId: String?
    var convertedCnyAmountText: String?
    var recurrenceRule: String?
    var note: String?

    func validationError(accounts: [AccountDTO], categories: [CategoryDTO]) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写标题" }
        guard let amount = parseDecimalAmount(amountText), amount > 0 else { return "金额无效" }
        if let accountId, !accounts.contains(where: { $0.id == accountId }) {
            return "选中的账户已不可用，请重新选择或改为不关联"
        }
        if let categoryId, !categories.contains(where: { $0.id == categoryId }) {
            return "选中的分类已不可用，请重新选择或改为不关联"
        }
        return nil
    }

    func toRequest() throws -> CashFlowItemCreateRequest {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProposalDraftError.message("请填写标题")
        }
        guard let amount = parseDecimalAmount(amountText), amount > 0 else {
            throw AIProposalDraftError.message("金额无效")
        }
        return CashFlowItemCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            direction: direction,
            cashFlowType: cashFlowType,
            amount: DecimalValue(amount),
            currency: currency,
            exchangeRateId: exchangeRateId,
            convertedCnyAmount: convertedCnyAmountText.flatMap(parseDecimalAmount).map(DecimalValue.init),
            expectedDate: expectedDate,
            accountId: accountId,
            categoryId: categoryId,
            recurrenceRule: recurrenceRule,
            note: note
        )
    }

    static func parse(_ payload: [String: JSONValueDTO]) -> EditableCashFlowDraft {
        EditableCashFlowDraft(
            title: JSONPayload.string(payload, "title") ?? "",
            direction: JSONPayload.string(payload, "direction") ?? "outflow",
            cashFlowType: JSONPayload.string(payload, "cash_flow_type") ?? "other",
            amountText: JSONPayload.amountText(payload, "amount"),
            currency: CurrencyCode(rawValue: (JSONPayload.string(payload, "currency") ?? "CNY").uppercased()) ?? .cny,
            expectedDate: JSONPayload.date(payload, "expected_date") ?? Date(),
            accountId: JSONPayload.string(payload, "account_id"),
            categoryId: JSONPayload.string(payload, "category_id"),
            exchangeRateId: JSONPayload.string(payload, "exchange_rate_id"),
            convertedCnyAmountText: JSONPayload.optionalAmountText(payload, "converted_cny_amount"),
            recurrenceRule: JSONPayload.string(payload, "recurrence_rule"),
            note: JSONPayload.string(payload, "note")
        )
    }
}

// MARK: - Payload (de)serialization helpers

/// Small, defensive readers over a raw `[String: JSONValueDTO]` action payload
/// (server-opaque `Dict[str, Any]` — never assumed to match a fixed
/// `CodingKeys` shape).
enum JSONPayload {
    static func string(_ dict: [String: JSONValueDTO], _ key: String) -> String? {
        guard case .string(let value)? = dict[key] else { return nil }
        return value
    }

    /// Amount fields arrive as JSON strings per the AI prompt's documented
    /// shape ("decimal string"), but tolerate a raw JSON number too — either
    /// way the result feeds a `TextField` + `parseDecimalAmount` at submit.
    static func amountText(_ dict: [String: JSONValueDTO], _ key: String) -> String {
        switch dict[key] {
        case .string(let value): return value
        case .number(let value): return trimmedNumber(value)
        default: return ""
        }
    }

    /// Same as `amountText` but returns nil (not "") when the key is absent —
    /// for optional passthrough amount fields where "" would wrongly become a
    /// present-but-empty override on rebuild.
    static func optionalAmountText(_ dict: [String: JSONValueDTO], _ key: String) -> String? {
        switch dict[key] {
        case .string(let value): return value
        case .number(let value): return trimmedNumber(value)
        default: return nil
        }
    }

    private static func trimmedNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    static func date(_ dict: [String: JSONValueDTO], _ key: String) -> Date? {
        guard let text = string(dict, key) else { return nil }
        return DateFormatter.linoAPIDate.date(from: text)
    }

    static func array(_ dict: [String: JSONValueDTO], _ key: String) -> [JSONValueDTO] {
        guard case .array(let items)? = dict[key] else { return [] }
        return items
    }

    static func object(_ value: JSONValueDTO?) -> [String: JSONValueDTO]? {
        guard case .object(let dict)? = value else { return nil }
        return dict
    }

    static func bool(_ dict: [String: JSONValueDTO], _ key: String) -> Bool {
        guard case .bool(let value)? = dict[key] else { return false }
        return value
    }
}

/// Re-encodes an already-shipped `Encodable` request type (the SAME shape
/// `POST /entries` / `POST /cash-flow-items` already accept) into the raw
/// `[String: JSONValueDTO]` an `AIActionProposalRequest.payload` needs, using
/// the identical JSON settings `LinoAPIClient` itself encodes with — so the
/// wire shape can never drift from what the ledger endpoints already validate.
enum AIProposalPayloadCoding {
    static func encode<T: Encodable>(_ value: T) throws -> [String: JSONValueDTO] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .formatted(.linoAPIDate)
        let data = try encoder.encode(value)
        return try JSONDecoder().decode([String: JSONValueDTO].self, from: data)
    }
}
