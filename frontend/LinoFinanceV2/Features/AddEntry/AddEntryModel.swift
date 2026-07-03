import Foundation

/// Sanitizes raw keystroke input for the 记一笔 big-amount field (macOS
/// `AddEntryPage` + iOS `AddEntryIOSSheet` share this — v2.5.0 P2 item B):
/// keep digits only, allow at most one "." separator, and cap the fractional
/// part at 2 digits (typing a 3rd decimal digit is simply dropped, not
/// rejected — matches how native currency keypads behave). Does not affect
/// `Decimal(string:)` parsing at submit time, which already only accepts the
/// resulting clean string.
func sanitizeAmountInput(_ raw: String) -> String {
    var seenDot = false
    var fractionDigits = 0
    var result = ""
    for ch in raw {
        if ch == "." {
            guard !seenDot else { continue }
            seenDot = true
            result.append(ch)
        } else if ch.isNumber {
            if seenDot {
                guard fractionDigits < 2 else { continue }
                fractionDigits += 1
            }
            result.append(ch)
        }
        // Any other character (letters, symbols, whitespace) is dropped.
    }
    return result
}

// AddEntryModel — D3 记一笔 form state + the double-entry mapping (P2 core).
//
// Mapping follows the v1 golden reference `MacQuickEntryView.submitForm()` +
// `QuickEntryCore.QuickEntryIntent` (those live in the v1 target, NOT shared Core,
// so the direction/movement-type derivation is re-expressed here), extended with
// the 转账 segment and dual-currency (CNY/USD) per HANDOFF §4.3 + §5.
//
// Four simple-mode segments → EntryCreateRequest:
//   支出   intent.expense       categoryLines=[expense line]  movements=[balance_out]   entryType "single"
//   收入   intent.income        categoryLines=[income line]   movements=[balance_in]    entryType "single"
//   信用消费 intent.creditCharge categoryLines=[expense line]  movements=[credit_charge] entryType "single"
//   转账   (no category)         categoryLines=[]              movements=[transfer_out, transfer_in] entryType "transfer"
// status is ALWAYS .confirmed (no draft, v1.4.0 口径).
//
// USD: a USD line/movement carries `exchangeRateId` = the latest USD→CNY rate id
// (locks the historical rate the way the backend would auto-resolve). We leave
// `convertedCnyAmount = nil` and let the backend compute it — the ledger service
// (`_resolve_payload_conversion`) accepts nil and computes amount×rate; if we sent
// a value it would have to match exactly or 400. The exchange_rate_id is itself
// optional server-side (auto-resolves latest ≤ entry_date) but we pin it so the
// row is explicit and the "将写入" preview can show it. Account-movement currency
// MUST equal the account's currency, so USD entries require a USD account.

enum AddEntrySegment: String, CaseIterable, Identifiable {
    case expense
    case income
    case creditCharge
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .creditCharge: "信用消费"
        case .transfer: "转账"
        }
    }

    /// Category direction for the non-transfer segments (v1 `QuickEntryIntent`
    /// mapping: expense & creditCharge → expense; income → income). Transfer has
    /// no category line.
    var categoryDirection: CategoryDirection? {
        switch self {
        case .income: .income
        case .expense, .creditCharge: .expense
        case .transfer: nil
        }
    }

    /// Single account-movement type for the non-transfer segments (v1
    /// `QuickEntryIntent.movementType`). Transfer uses two movements directly.
    var singleMovementType: MovementType? {
        switch self {
        case .income: .balanceIn
        case .expense: .balanceOut
        case .creditCharge: .creditCharge
        case .transfer: nil
        }
    }

    var needsCategory: Bool { self != .transfer }
}

/// A line in the optional "将写入" double-entry preview (HANDOFF §4.3).
struct EntryPreviewLine: Identifiable {
    let id = UUID()
    /// "分类行" or "账户流水"
    let kind: String
    /// e.g. "餐饮" / "招商储蓄 balance_out"
    let label: String
    let amount: DecimalValue
    let currency: CurrencyCode
    /// Negative = outflow (red), positive = inflow (green), nil = neutral.
    let signedNegative: Bool?
}

/// Errors surfaced verbatim to the form footer (visible, never silent).
enum AddEntryError: LocalizedError {
    case missingTitle
    case invalidAmount
    case missingCategory
    case missingAccount
    case missingTransferAccounts
    case sameTransferAccounts
    case noUSDRate
    case reimbursementNeedsDate

    var errorDescription: String? {
        switch self {
        case .missingTitle: "请输入标题。"
        case .invalidAmount: "请输入有效的正金额。"
        case .missingCategory: "请选择分类。"
        case .missingAccount: "请选择账户。"
        case .missingTransferAccounts: "请选择转出和转入账户。"
        case .sameTransferAccounts: "转出和转入账户不能相同。"
        case .noUSDRate: "没有可用的美元汇率，无法记 USD 记录。请先在设置里维护汇率。"
        case .reimbursementNeedsDate: "可报销记录需要填写预计报销日期。"
        }
    }
}

/// Pure mapping helper — turns form state into a validated `EntryCreateRequest`.
/// Kept separate from the View so the double-entry logic is testable / inspectable.
struct AddEntryMapper {

    struct Input {
        var segment: AddEntrySegment
        var title: String
        var amount: Decimal
        var currency: CurrencyCode
        var date: Date
        var categoryId: String?
        var accountId: String?            // expense/income/creditCharge + transfer-OUT
        var transferInAccountId: String?  // transfer-IN
        var reimbursable: Bool
        var reimbursementPayer: String?
        var reimbursementExpectedDate: Date?
        /// id of the latest USD→CNY rate (nil if none exists).
        var usdRateId: String?
    }

    /// Build the request, throwing a visible `AddEntryError` on any gap.
    static func makeRequest(_ input: Input) throws -> EntryCreateRequest {
        let cleanTitle = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw AddEntryError.missingTitle }
        guard input.amount > 0 else { throw AddEntryError.invalidAmount }

        // USD requires a rate row to pin (account movement currency must match the
        // account; lines convert through this rate).
        let exchangeRateId: String?
        if input.currency == .usd {
            guard let id = input.usdRateId else { throw AddEntryError.noUSDRate }
            exchangeRateId = id
        } else {
            exchangeRateId = nil
        }

        let amount = DecimalValue(input.amount)

        switch input.segment {
        case .transfer:
            guard let out = input.accountId, let into = input.transferInAccountId else {
                throw AddEntryError.missingTransferAccounts
            }
            guard out != into else { throw AddEntryError.sameTransferAccounts }

            let movements = [
                AccountMovementCreateRequest(
                    accountId: out,
                    statementCycleId: nil,
                    movementType: .transferOut,
                    amount: amount,
                    currency: input.currency,
                    exchangeRateId: exchangeRateId,
                    convertedCnyAmount: nil
                ),
                AccountMovementCreateRequest(
                    accountId: into,
                    statementCycleId: nil,
                    movementType: .transferIn,
                    amount: amount,
                    currency: input.currency,
                    exchangeRateId: exchangeRateId,
                    convertedCnyAmount: nil
                ),
            ]
            return EntryCreateRequest(
                title: cleanTitle,
                entryType: "transfer",
                date: input.date,
                status: .confirmed,
                categoryLines: [],
                accountMovements: movements
            )

        case .expense, .income, .creditCharge:
            guard let movementType = input.segment.singleMovementType,
                  let direction = input.segment.categoryDirection else {
                throw AddEntryError.missingCategory
            }
            guard let categoryId = input.categoryId else { throw AddEntryError.missingCategory }
            guard let accountId = input.accountId else { throw AddEntryError.missingAccount }

            if input.reimbursable && input.reimbursementExpectedDate == nil {
                throw AddEntryError.reimbursementNeedsDate
            }

            let line = EntryCategoryLineCreateRequest(
                categoryId: categoryId,
                direction: direction,
                amount: amount,
                currency: input.currency,
                exchangeRateId: exchangeRateId,
                convertedCnyAmount: nil,
                reimbursableFlag: input.reimbursable,
                reimbursementPayer: input.reimbursable ? input.reimbursementPayer : nil,
                reimbursementExpectedDate: input.reimbursable ? input.reimbursementExpectedDate : nil,
                // v2.1.0 P2: reimbursement collapsed to three states; a new
                // reimbursable line starts as "pending" (server default).
                reimbursementStatus: input.reimbursable ? "pending" : nil
            )
            let movement = AccountMovementCreateRequest(
                accountId: accountId,
                statementCycleId: nil,
                movementType: movementType,
                amount: amount,
                currency: input.currency,
                exchangeRateId: exchangeRateId,
                convertedCnyAmount: nil
            )
            return EntryCreateRequest(
                title: cleanTitle,
                entryType: "single",
                date: input.date,
                status: .confirmed,
                categoryLines: [line],
                accountMovements: movement.asArray
            )
        }
    }
}

private extension AccountMovementCreateRequest {
    var asArray: [AccountMovementCreateRequest] { [self] }
}
