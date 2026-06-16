import Foundation
import SwiftUI

#if os(macOS)

// ReconciliationModel — v2.2.0 对账「一致性/冲突检测器」view-model (macOS).
//
// v2.2.0 推倒重做：旧 model 拿 `GET /reconciliation/accounts`（两个恒等内部数相减、
// 永远「无需调整」）。现在改驱动 `GET /reconciliation/check`——逐账户 + 跨对象孤儿的
// 多维冲突清单，每条 conflict 带 `fix`（重算 / 跳转记录 / 录真实数）指明纠错路径。
//
// 三条纠错动作：
//   • R1 信用欠款漂移 → recompute(accountID:)  → POST /reconciliation/recompute-credit/{id}
//   • R3 余额↔真实    → submitAdjustment(...)   → POST /reconciliation/adjustments
//   • R2/R4 跳转       → 纯前端导航（screen 自己处理），无 model 动作
@MainActor
final class ReconciliationModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var snapshot: ReconciliationCheckResponseDTO?
    @Published private(set) var state: LoadState = .idle

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    var accounts: [ReconciliationCheckAccountDTO] { snapshot?.accounts ?? [] }
    var orphans: [ReconciliationConflictDTO] { snapshot?.orphans ?? [] }
    var hasConflicts: Bool { snapshot?.hasConflicts ?? false }

    /// 有冲突的账户（红标）置顶，无冲突在后；孤儿单列展示。
    var sortedAccounts: [ReconciliationCheckAccountDTO] {
        accounts.sorted { lhs, rhs in
            if lhs.hasConflicts != rhs.hasConflicts { return lhs.hasConflicts }
            return lhs.accountName < rhs.accountName
        }
    }

    var conflictAccountCount: Int { accounts.filter(\.hasConflicts).count }
    var orphanConflictCount: Int { orphans.filter(\.isConflict).count }

    func load() async {
        state = .loading
        do {
            snapshot = try await apiClient.reconciliationCheck()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// R1 信用欠款重算对平：`current_liability := Σcycle`，差额记 adjustment。重算后
    /// 刷新快照让冲突归正。抛出底层错误供 caller 显示。
    @discardableResult
    func recompute(accountID: String) async throws -> CreditRecomputeResponseDTO {
        let result = try await apiClient.recomputeCreditLiability(accountID: accountID)
        await load()
        return result
    }

    /// R3 余额账户「录真实余额」对平：用户填真实数，后端算 delta、写 AccountAdjustment、
    /// 设账户余额。重新加载快照让 R3 归零。
    @discardableResult
    func submitAdjustment(
        accountId: String,
        actualAmount: DecimalValue,
        reason: String,
        note: String?
    ) async throws -> AccountAdjustmentDTO {
        let request = AccountAdjustmentCreateRequest(
            accountId: accountId,
            actualAmount: actualAmount,
            reason: reason,
            note: note
        )
        let result = try await apiClient.createAccountAdjustment(request)
        await load()
        return result
    }
}

#endif
