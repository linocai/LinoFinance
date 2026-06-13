import Foundation
import SwiftUI

#if os(macOS)

// ReimbursementsModel — D6 报销 view-model.
//
// Owns the claim list + the report summary + the data the "new claim" form needs
// (entries to link a claim onto). State machine (plan §D6):
//   reimbursable → invoice_pending → submitted → approved → waiting_received → received
// (+ side states rejected / abandoned / partial_received). The screen maps each
// status onto its allowed actions; this model just wraps the client calls and
// reloads on success.
//
// Business semantics carried over from v1 ReimbursementsView:
//   • create  — links a claim to an EXISTING confirmed entry + one of its
//               category lines (amount/currency/rate inherited from the line).
//   • receive — builds a confirmed *income* entry into a matching-currency
//               balance account, then POSTs mark-received with that entry.
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

    // MARK: - State actions

    func submit(_ id: String) async throws {
        _ = try await apiClient.submitReimbursementClaim(id)
        await load()
    }

    func approve(_ id: String) async throws {
        _ = try await apiClient.approveReimbursementClaim(id)
        await load()
    }

    func reject(_ id: String) async throws {
        _ = try await apiClient.rejectReimbursementClaim(id)
        await load()
    }

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

    // MARK: - Receive (builds an income settlement entry, plan §D6)

    /// Mark a claim received into a balance account whose currency matches the
    /// claim. Throws a clear error if no matching account / income category exists.
    func markReceived(
        _ claim: ReimbursementClaimDTO,
        accounts: [AccountDTO],
        categories: [CategoryDTO]
    ) async throws {
        guard let account = accounts.first(where: {
            $0.type == .balance && $0.status == "active" && $0.currency == claim.currency
        }) else {
            throw ReimbursementError.noMatchingAccount(claim.currency)
        }
        guard let category = categories.first(where: { $0.isActive && $0.type == .income }) else {
            throw ReimbursementError.noIncomeCategory
        }
        // Greppable trace back to the originating claim (no claim_id FK on entries).
        let traceNote = "[claim:\(claim.id)] " + (claim.note ?? "")
        let entry = EntryCreateRequest(
            title: "报销到账",
            date: Date(),
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
            actualReceivedDate: Date(),
            receivedAccountId: account.id,
            entry: entry
        )
        _ = try await apiClient.markReimbursementReceived(claim.id, request: request)
        await load()
    }

    /// Names the receiving account for the confirmation copy (or nil if none).
    func receivingAccountName(for claim: ReimbursementClaimDTO, accounts: [AccountDTO]) -> String? {
        accounts.first(where: {
            $0.type == .balance && $0.status == "active" && $0.currency == claim.currency
        })?.name
    }
}

enum ReimbursementError: LocalizedError {
    case noMatchingAccount(CurrencyCode)
    case noIncomeCategory

    var errorDescription: String? {
        switch self {
        case .noMatchingAccount(let currency):
            return "标记到账需要一个启用的 \(currency.rawValue) 余额账户"
        case .noIncomeCategory:
            return "标记到账需要至少一个启用的收入分类"
        }
    }
}

#endif
