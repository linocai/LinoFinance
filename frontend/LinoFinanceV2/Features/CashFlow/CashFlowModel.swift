import Foundation
import SwiftUI

// CashFlowModel — D4 现金流 feature view-model (P3).
//
// Owns its own load/error state on the shared `LinoAPIClient` (P2 architecture).
// Lists cash-flow items (cancelled hidden by default), drives the three per-row
// actions (确认 / 兑现settle / 取消) and create / edit.
//
// SETTLE rules (v2.1.0 P1 — transfer 信用还款直接结算放开):
//   • transfer items (credit repayment) settle in-place via the 确认还款 sheet:
//     pick the repayment SOURCE balance account + date → build a transfer-only
//     entry (transfer_out on the source + credit_repayment on the credit account)
//     and settle. The source account is distinct from `item.accountId` (which
//     holds the CREDIT account for a system-generated repayment item), so we never
//     PATCH it onto the item; the credit leg + statement cycle come from the item.
//   • reimbursement-linked items settle only via the claim's mark-received →
//     no direct settle (backend rejects a direct settle; audit 1.3).
//   • an inflow/outflow settle needs an `account_id` + `category_id`. If both
//     already set we build the entry and settle in one shot; if missing, the UI
//     gathers them (SettleCompletionSheet) and PATCHes them first, then settles.

@MainActor
final class CashFlowModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var items: [CashFlowItemDTO] = []
    @Published private(set) var accounts: [AccountDTO] = []
    @Published private(set) var categories: [CategoryDTO] = []
    @Published private(set) var state: LoadState = .idle
    /// Inline error from a row action (confirm/settle/cancel), surfaced as a banner.
    @Published var actionError: String?

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Derived

    /// Active rows first (expected/confirmed), settled drops to the bottom; within
    /// each bucket preserve the server's expected_date order (v1 ordering).
    var sortedItems: [CashFlowItemDTO] {
        items.sorted { lhs, rhs in
            let lhsDone = lhs.status == "settled"
            let rhsDone = rhs.status == "settled"
            if lhsDone != rhsDone { return !lhsDone }
            return lhs.expectedDate < rhs.expectedDate
        }
    }

    func accountName(_ id: String?) -> String? {
        guard let id else { return nil }
        return accounts.first(where: { $0.id == id })?.name
    }

    // MARK: - Load

    /// cancelled hidden by default (includeCancelled: false).
    func load() async {
        if items.isEmpty { state = .loading }
        do {
            async let itemsResult = apiClient.listCashFlowItems(includeCancelled: false)
            async let accountsResult = apiClient.listAccounts()
            async let categoriesResult = apiClient.listCategories()
            items = try await itemsResult
            accounts = (try? await accountsResult) ?? accounts
            categories = (try? await categoriesResult) ?? categories
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Create / edit

    func create(_ request: CashFlowItemCreateRequest) async throws {
        _ = try await apiClient.createCashFlowItem(request)
        await load()
    }

    func update(_ id: String, request: CashFlowItemUpdateRequest) async throws {
        _ = try await apiClient.updateCashFlowItem(id, request: request)
        await load()
    }

    // MARK: - Row actions

    func confirm(_ id: String) async {
        do {
            _ = try await apiClient.confirmCashFlowItem(id)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func cancel(_ id: String) async {
        do {
            _ = try await apiClient.cancelCashFlowItem(id)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Settle outcome: either done, or needs the completion sheet (missing
    /// account/category for inflow/outflow), or needs the 确认还款 sheet (transfer),
    /// or blocked (reimbursement-linked).
    enum SettleOutcome {
        case settled
        case needsCompletion
        /// Transfer (credit repayment): caller opens the 确认还款 sheet to pick a
        /// repayment source balance account + date.
        case needsRepaymentSource
        case blocked(String)
    }

    /// Attempt the one-shot settle. Returns `.needsCompletion`/`.needsRepaymentSource`
    /// when the caller must gather more input before settling.
    func attemptSettle(_ item: CashFlowItemDTO) async -> SettleOutcome {
        if item.linkedReimbursementId != nil {
            return .blocked("报销关联现金流请通过报销中心的「标记到账」结算。")
        }
        if item.direction == "transfer" {
            // Transfer = 信用还款: always gather the repayment source via the sheet.
            return .needsRepaymentSource
        }
        guard item.accountId != nil, item.categoryId != nil else {
            return .needsCompletion
        }
        do {
            try await settle(item)
            return .settled
        } catch {
            actionError = error.localizedDescription
            return .settled   // error surfaced via banner; sheet stays closed
        }
    }

    /// Build the settle `EntryCreateRequest` from a fully-linked item and POST it
    /// (mirrors v1 `runSettle`). Throws on a still-missing link.
    func settle(_ item: CashFlowItemDTO) async throws {
        guard let accountId = item.accountId, let categoryId = item.categoryId else {
            actionError = "结算需要现金流已关联账户和分类。"
            return
        }
        let isInflow = item.direction == "inflow"
        let entry = EntryCreateRequest(
            title: item.title,
            date: Date(),
            status: .confirmed,
            note: item.note,
            categoryLines: [
                EntryCategoryLineCreateRequest(
                    categoryId: categoryId,
                    direction: isInflow ? .income : .expense,
                    amount: item.amount,
                    currency: item.currency,
                    exchangeRateId: item.exchangeRateId,
                    convertedCnyAmount: item.convertedCnyAmount,
                    note: item.note
                )
            ],
            accountMovements: [
                AccountMovementCreateRequest(
                    accountId: accountId,
                    statementCycleId: item.linkedStatementCycleId,
                    movementType: isInflow ? .balanceIn : .balanceOut,
                    amount: item.amount,
                    currency: item.currency,
                    exchangeRateId: item.exchangeRateId,
                    convertedCnyAmount: item.convertedCnyAmount,
                    note: item.note
                )
            ]
        )
        _ = try await apiClient.settleCashFlowItem(item.id, request: CashFlowSettleRequest(entry: entry))
        await load()
    }

    /// Completion path: PATCH the chosen account/category, then settle the
    /// freshly-linked item (mirrors v1 `SettleCompletionSheet.submit`).
    func completeAndSettle(_ item: CashFlowItemDTO, accountId: String, categoryId: String) async throws {
        _ = try await apiClient.updateCashFlowItem(
            item.id,
            request: CashFlowItemUpdateRequest(accountId: .value(accountId), categoryId: .value(categoryId))
        )
        await load()
        guard let refreshed = items.first(where: { $0.id == item.id }) else {
            throw CashFlowError.itemGone
        }
        try await settle(refreshed)
    }

    // MARK: - Transfer (信用还款) direct settle (v2.1.0 P1)

    /// Balance accounts in the item's currency, eligible as a repayment source.
    func repaymentSourceAccounts(for item: CashFlowItemDTO) -> [AccountDTO] {
        accounts
            .filter { $0.type == .balance && $0.status == "active" && $0.currency == item.currency }
            .sorted(by: AccountDTO.displayOrdered)
    }

    /// The credit account being repaid (the item's linked account for a
    /// system-generated repayment item). Nil for a manual transfer with no link.
    func repaidCreditAccount(for item: CashFlowItemDTO) -> AccountDTO? {
        guard let id = item.accountId else { return nil }
        return accounts.first { $0.id == id && $0.type == .credit }
    }

    /// Settle a transfer (信用还款) item directly: build a transfer-only entry that
    /// moves money out of the chosen source balance account and pays down the
    /// credit account's liability + statement cycle, then settle. The source
    /// account is NOT written onto the item (it would clobber the credit link).
    ///
    /// Entry shape (matches the canonical credit-repayment double entry):
    ///   category_lines: []  (backend rejects category lines on a transfer settle)
    ///   account_movements:
    ///     • transfer_out on the source balance account (reduces its balance)
    ///     • credit_repayment on the credit account, carrying the item's
    ///       linked_statement_cycle_id (reduces liability + cycle paid amount)
    /// Falls back to a plain transfer_out/transfer_in when the item is a manual
    /// transfer with no statement cycle (no credit leg available).
    func settleRepayment(_ item: CashFlowItemDTO, sourceAccountId: String, date: Date) async throws {
        let creditLeg: AccountMovementCreateRequest
        if let cycleId = item.linkedStatementCycleId, let creditAccountId = item.accountId {
            creditLeg = AccountMovementCreateRequest(
                accountId: creditAccountId,
                statementCycleId: cycleId,
                movementType: .creditRepayment,
                amount: item.amount,
                currency: item.currency,
                exchangeRateId: item.exchangeRateId,
                convertedCnyAmount: item.convertedCnyAmount,
                note: item.note
            )
        } else if let destinationAccountId = item.accountId {
            // Manual transfer with no credit cycle → plain transfer into the linked account.
            creditLeg = AccountMovementCreateRequest(
                accountId: destinationAccountId,
                statementCycleId: nil,
                movementType: .transferIn,
                amount: item.amount,
                currency: item.currency,
                exchangeRateId: item.exchangeRateId,
                convertedCnyAmount: item.convertedCnyAmount,
                note: item.note
            )
        } else {
            throw CashFlowError.noRepaymentTarget
        }

        let sourceLeg = AccountMovementCreateRequest(
            accountId: sourceAccountId,
            statementCycleId: nil,
            movementType: .transferOut,
            amount: item.amount,
            currency: item.currency,
            exchangeRateId: item.exchangeRateId,
            convertedCnyAmount: item.convertedCnyAmount,
            note: item.note
        )

        let entry = EntryCreateRequest(
            title: item.title,
            entryType: "transfer",
            date: date,
            status: .confirmed,
            note: item.note,
            categoryLines: [],
            accountMovements: [sourceLeg, creditLeg]
        )
        _ = try await apiClient.settleCashFlowItem(item.id, request: CashFlowSettleRequest(entry: entry))
        await load()
    }
}

enum CashFlowError: LocalizedError {
    case itemGone
    case noRepaymentTarget

    var errorDescription: String? {
        switch self {
        case .itemGone: "结算失败：现金流已不在列表中。"
        case .noRepaymentTarget: "结算失败：这条转账现金流没有可还款的目标账户。"
        }
    }
}

// MARK: - Display vocabulary

extension CashFlowItemDTO {
    /// Whether the settle action may be offered. Reimbursement-linked receivables
    /// settle through the claim's mark-received, so the entry point is hidden here.
    /// Transfers (信用还款) ARE settleable in-place now (v2.1.0 P1) — they route
    /// to the 确认还款 sheet instead of the generic completion sheet.
    var canShowSettleAction: Bool {
        linkedReimbursementId == nil
    }

    var statusTitle: String {
        switch status {
        case "expected": "预计"
        case "confirmed": "已确认"
        case "settled": "已兑现"
        case "cancelled": "已取消"
        default: status
        }
    }

    var statusTone: StatusBadge.Tone {
        switch status {
        case "expected": .pending
        case "confirmed": .brand
        case "settled": .positive
        case "cancelled": .negative
        default: .neutral
        }
    }

    var directionTitle: String {
        switch direction {
        case "inflow": "进账"
        case "outflow": "出账"
        case "transfer": "转账"
        default: direction
        }
    }
}

/// 现金流类型中文名（v1 financeStatusTitle 口径的子集）。
enum CashFlowType {
    static let allCases = [
        "salary", "rent_income", "reimbursement", "subscription",
        "credit_repayment", "installment", "one_time", "other"
    ]

    static func title(_ raw: String) -> String {
        switch raw {
        case "salary": "工资"
        case "rent_income": "租金收入"
        case "reimbursement": "报销"
        case "subscription": "订阅"
        case "credit_repayment": "信用还款"
        case "installment": "分期"
        case "one_time": "一次性"
        case "other": "其他"
        default: raw
        }
    }
}
