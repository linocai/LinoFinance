import Foundation
import SwiftUI

#if os(macOS)

// ReimbursementsModel — v2.1.0 P2 报销 view-model (three-state).
//
// Owns the claim list + the report summary + the data the "new claim" form needs
// (entries to link a claim onto). The status machine is collapsed to three
// single-user states (PROJECT_PLAN §5.7 D1):
//   pending (待回款) → received (已到账)   |   pending → abandoned (已放弃)
// The screen surfaces only two row actions: 确认到账 (pending → received) and
// 放弃 (pending → abandoned). The submit/approve/reject ceremony is gone.
//
// Business semantics:
//   • create  — links a claim to an EXISTING confirmed entry + one of its
//               category lines (amount/currency/rate inherited from the line);
//               the server defaults the new claim to `pending`.
//   • receive — the user EXPLICITLY picks the receiving balance account, the
//               income category, and the actual received date in a sheet (D-T3);
//               this model builds the confirmed *income* entry from those choices
//               and POSTs mark-received with it. No silent "first matching
//               account / first income category" guessing.
@MainActor
final class ReimbursementsModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var claims: [ReimbursementClaimDTO] = []
    @Published private(set) var report: ReimbursementReportDTO?
    @Published private(set) var entries: [EntryDTO] = []
    @Published private(set) var state: LoadState = .idle
    @Published var reportView: String = "personal_net"

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Loads

    func load() async {
        state = .loading
        do {
            async let claimsResult = apiClient.listReimbursementClaims()
            async let reportResult = apiClient.reimbursementReport(view: reportView)
            claims = try await claimsResult
            report = try? await reportResult
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Confirmed entries (for the link picker). Lazy — only loaded when the new
    /// claim sheet opens.
    func loadEntries() async {
        if let result = try? await apiClient.listEntries() {
            entries = result.filter { $0.status == .confirmed }
        }
    }

    func reloadReport() async {
        report = try? await apiClient.reimbursementReport(view: reportView)
    }

    // MARK: - State actions (three-state)

    /// Give up an outstanding receivable (pending → abandoned). The linked
    /// reimbursement cash flow is cancelled server-side.
    func abandon(_ id: String) async throws {
        _ = try await apiClient.abandonReimbursementClaim(id)
        await load()
    }

    // MARK: - Create

    @discardableResult
    func createClaim(
        entry: EntryDTO,
        line: EntryCategoryLineDTO,
        payer: String,
        expectedDate: Date,
        note: String?
    ) async throws -> ReimbursementClaimDTO {
        let request = ReimbursementClaimCreateRequest(
            linkedEntryId: entry.id,
            linkedEntryLineId: line.id,
            amount: line.amount,
            currency: line.currency,
            exchangeRateId: line.exchangeRateId,
            convertedCnyAmount: line.convertedCnyAmount,
            payer: payer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "company" : payer,
            expectedDate: expectedDate,
            note: note
        )
        let claim = try await apiClient.createReimbursementClaim(request)
        await load()
        return claim
    }

    // MARK: - Receive (user-chosen account + category + date, D-T3)

    /// Mark a claim received using the account / category / date the user
    /// explicitly picked in the confirmation sheet. Builds a confirmed income
    /// entry into `account` and POSTs mark-received with it (pending → received).
    func markReceived(
        _ claim: ReimbursementClaimDTO,
        into account: AccountDTO,
        incomeCategory category: CategoryDTO,
        receivedDate: Date
    ) async throws {
        // Greppable trace back to the originating claim (no claim_id FK on entries).
        let traceNote = "[claim:\(claim.id)] " + (claim.note ?? "")
        let entry = EntryCreateRequest(
            title: "报销到账",
            date: receivedDate,
            status: .confirmed,
            note: traceNote,
            categoryLines: [
                EntryCategoryLineCreateRequest(
                    categoryId: category.id,
                    direction: .income,
                    amount: claim.amount,
                    currency: claim.currency,
                    exchangeRateId: claim.exchangeRateId,
                    convertedCnyAmount: claim.convertedCnyAmount,
                    note: traceNote
                )
            ],
            accountMovements: [
                AccountMovementCreateRequest(
                    accountId: account.id,
                    statementCycleId: nil,
                    movementType: .balanceIn,
                    amount: claim.amount,
                    currency: claim.currency,
                    exchangeRateId: claim.exchangeRateId,
                    convertedCnyAmount: claim.convertedCnyAmount,
                    note: traceNote
                )
            ]
        )
        let request = ReimbursementReceiveRequest(
            actualReceivedDate: receivedDate,
            receivedAccountId: account.id,
            entry: entry
        )
        _ = try await apiClient.markReimbursementReceived(claim.id, request: request)
        await load()
    }

    /// Active balance accounts whose currency matches the claim — the only valid
    /// receiving accounts for the confirmation sheet picker.
    func eligibleAccounts(for claim: ReimbursementClaimDTO, accounts: [AccountDTO]) -> [AccountDTO] {
        accounts.filter {
            $0.type == .balance && $0.status == "active" && $0.currency == claim.currency
        }
    }

    /// Active income categories — the valid options for the confirmation sheet.
    func incomeCategories(_ categories: [CategoryDTO]) -> [CategoryDTO] {
        categories.filter { $0.isActive && $0.type == .income }
    }
}

#endif
