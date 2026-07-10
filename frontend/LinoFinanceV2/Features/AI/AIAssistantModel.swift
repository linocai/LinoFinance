import Foundation
import SwiftUI

// AIAssistantModel — v3.0.0 P4 ① 自然语言 → 提案 → (可编辑) 确认 → 执行的跨平台
// view-model, shared verbatim by the macOS AI 屏 (`AIScreen`) and the iOS
// 记一笔「AI 解析」sheet (`AIProposalSheetIOS`) — D5.
//
// Deliberately does NOT hold a reference to `AppModel`. Callers (the views)
// read this model's published state after each `await` and decide whether the
// wider app state needs a refresh: `.executed` outcomes mutate the ledger (an
// entry / cash-flow item was created, or an executed action was rolled back)
// so the caller should `await model.refreshAll()`; everything else (create a
// proposal, approve, reject, discard) is plan-bookkeeping only. This mirrors
// how sibling feature models (CashFlowModel, AccountsModel) stay decoupled
// from AppModel and let the view orchestrate cross-model refreshes.
//
// Resubmit-on-confirm design: `prepareExecution` ALWAYS creates a fresh plan
// from the (possibly user-edited) `editableActions` — even if nothing was
// edited — rather than trying to diff against the original and reuse it. This
// keeps one uniform, easy-to-reason-about code path (the server recomputes
// risk_level from what's ACTUALLY about to be sent, whether that's an AI
// proposal a human left untouched or one with corrected account/category ids),
// at the cost of a few extra cheap round-trips on the common no-edit path. The
// ORIGINAL draft/history plan is only rejected on full success — a failure
// anywhere leaves it untouched so nothing is cleaned up based on a guess and
// the user's edits are never silently lost.
@MainActor
final class AIAssistantModel: ObservableObject {

    enum SectionState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    enum ExecutionOutcome: Equatable {
        case executed
        case awaitingHighRiskConfirm
        case failed
    }

    // MARK: - History (近期提案)

    @Published private(set) var historyState: SectionState = .idle
    @Published private(set) var history: [AIPlanDTO] = []

    // MARK: - Config status (read-only "未配置" banner gate)

    @Published private(set) var configState: SectionState = .idle
    @Published private(set) var config: AIConfigDTO?

    // MARK: - Draft under review

    @Published private(set) var draftPlan: AIPlanDTO?
    /// Not `private(set)` — the review UI binds directly into individual
    /// actions' nested drafts (account/category pickers, amount fields).
    @Published var editableActions: [EditableAIAction] = []
    /// Set once `prepareExecution` resubmits the edited actions and the server
    /// comes back with `risk_level == "high"` — approved but NOT yet executed;
    /// the view must show a distinct strong-confirm gate before calling
    /// `confirmHighRiskExecution()`.
    @Published private(set) var pendingHighRiskPlan: AIPlanDTO?

    @Published var sourceText: String = ""
    @Published private(set) var isParsing = false
    @Published private(set) var isSubmittingDraft = false
    @Published var actionError: String?

    let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    var hasDraft: Bool { draftPlan != nil }

    /// base_url + api_key + model 三者都有才算真正可用 — 与 `AIConfigModel`
    /// 同一口径 (两处各自 GET 一次，非共享实例——都是廉价只读调用).
    var isConfigured: Bool {
        guard let config else { return false }
        return config.baseUrlConfigured && config.apiKeyConfigured
            && !(config.model ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Loads

    func loadConfigStatus() async {
        configState = .loading
        do {
            config = try await apiClient.aiConfig()
            configState = .loaded
        } catch {
            configState = .failed(error.localizedDescription)
        }
    }

    func loadHistory() async {
        historyState = .loading
        do {
            history = try await apiClient.listAIPlans()
            historyState = .loaded
        } catch {
            historyState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Draft lifecycle

    @discardableResult
    func submitSourceText() async -> Bool {
        // Re-entrancy guard (v3.0.0 评审 重要-2): a fast double-tap dispatches two
        // Tasks before `.disabled(isParsing)` re-renders; the second must bail
        // here (this line runs synchronously before any await, so the flag set
        // below is already visible to the second invocation) or it double-creates
        // a plan the server can't dedupe.
        guard !isParsing else { return false }
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isParsing = true
        defer { isParsing = false }
        do {
            actionError = nil
            let plan = try await apiClient.createAIPlan(AIPlanCreateRequest(sourceText: trimmed))
            openForEdit(plan)
            sourceText = ""
            await loadHistory()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    /// Loads an existing (non-terminal) plan — from `history`, or the one just
    /// created by `submitSourceText` — into the review/edit surface.
    /// Synchronous: list/detail responses already carry full `actions[]`, no
    /// extra fetch needed.
    func openForEdit(_ plan: AIPlanDTO) {
        draftPlan = plan
        editableActions = plan.actions.map(EditableAIAction.init(action:))
        pendingHighRiskPlan = nil
        actionError = nil
    }

    func discardDraft() {
        draftPlan = nil
        editableActions = []
        pendingHighRiskPlan = nil
        actionError = nil
    }

    @discardableResult
    func rejectDraft() async -> Bool {
        guard let plan = draftPlan else { return false }
        do {
            actionError = nil
            _ = try await apiClient.rejectAIPlan(plan.id)
            discardDraft()
            await loadHistory()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: - Execute

    /// Validates every editable action against the CURRENT account/category
    /// lists (never trusts a stale/fabricated id, even one the LLM originally
    /// supplied legitimately — the account could have been deleted since), and
    /// — if clean — resubmits them as a fresh plan, approves it, and either
    /// executes immediately (low/medium risk) or stops for the high-risk gate.
    func prepareExecution(accounts: [AccountDTO], categories: [CategoryDTO]) async -> ExecutionOutcome {
        // Re-entrancy guard (v3.0.0 评审 重要-2): a fast double-tap dispatches two
        // Tasks before `.disabled(isSubmittingDraft)` re-renders; the second must
        // bail here — this line runs synchronously before any await, so the flag
        // set below is already visible — or each派生 a fresh `createAIPlan` (new
        // id) the server can't dedupe → the same spend lands twice.
        guard !isSubmittingDraft else { return .failed }
        guard let originalPlan = draftPlan else { return .failed }
        if let error = firstValidationError(accounts: accounts, categories: categories) {
            actionError = error
            return .failed
        }
        isSubmittingDraft = true
        defer { isSubmittingDraft = false }
        do {
            actionError = nil
            let proposals = try editableActions.map { try $0.toProposalRequest() }
            let newPlan = try await apiClient.createAIPlan(
                AIPlanCreateRequest(sourceText: originalPlan.sourceText, actions: proposals)
            )
            let approved = try await apiClient.approveAIPlan(newPlan.id)
            if newPlan.riskLevel == "high" {
                pendingHighRiskPlan = approved
                await loadHistory()
                return .awaitingHighRiskConfirm
            }
            // Execute is the ambiguous-failure step: the server may have already
            // committed the ledger write even though the response failed. On error
            // keep the draft (for retry) and warn the user to check history first
            // so a resubmit can't double-post (v3.0.0 评审 重要-3 前端缓解).
            do {
                _ = try await apiClient.executeAIPlan(approved.id)
            } catch {
                actionError = error.localizedDescription
                    + "\n重试前请到历史确认该提案状态，避免重复落账"
                return .failed
            }
            // Success: retire the original draft/history plan so it can't be
            // re-executed. If that best-effort reject fails we no longer swallow
            // it silently — surface a notice so the user reconciles history
            // (v3.0.0 评审 重要-3 前端缓解).
            var rejectFailed = false
            do {
                _ = try await apiClient.rejectAIPlan(originalPlan.id)
            } catch {
                rejectFailed = true
            }
            discardDraft()
            if rejectFailed {
                actionError = "已执行成功，但原草稿未能自动作废，请到历史核对避免重复"
            }
            await loadHistory()
            return .executed
        } catch {
            actionError = error.localizedDescription
            return .failed
        }
    }

    @discardableResult
    func confirmHighRiskExecution() async -> Bool {
        // Re-entrancy guard (v3.0.0 评审 重要-2): a double-tap on the strong-confirm
        // button would execute the already-approved high-risk plan twice. Bail
        // synchronously before any await; `prepareExecution`'s defer already
        // released the flag when it returned `.awaitingHighRiskConfirm`, so it is
        // free to reclaim here.
        guard !isSubmittingDraft else { return false }
        guard let plan = pendingHighRiskPlan, let originalPlan = draftPlan else { return false }
        isSubmittingDraft = true
        defer { isSubmittingDraft = false }
        actionError = nil
        // Execute is the ambiguous-failure step (see `prepareExecution`): warn the
        // user to check history before retrying (v3.0.0 评审 重要-3 前端缓解).
        do {
            _ = try await apiClient.executeAIPlan(plan.id, strongConfirm: "EXECUTE_HIGH_RISK")
        } catch {
            actionError = error.localizedDescription
                + "\n重试前请到历史确认该提案状态，避免重复落账"
            return false
        }
        var rejectFailed = false
        do {
            _ = try await apiClient.rejectAIPlan(originalPlan.id)
        } catch {
            rejectFailed = true
        }
        pendingHighRiskPlan = nil
        discardDraft()
        if rejectFailed {
            actionError = "已执行成功，但原草稿未能自动作废，请到历史核对避免重复"
        }
        await loadHistory()
        return true
    }

    /// User backs out of the high-risk gate. The plan was already approved
    /// server-side by `prepareExecution` — best-effort reject it so it doesn't
    /// linger as a mystery "approved, never executed" history row; the local
    /// draft (with the user's edits) is kept so they can adjust and retry, or
    /// discard entirely via the normal reject/cancel controls.
    func cancelHighRiskExecution() async {
        if let plan = pendingHighRiskPlan {
            try? await apiClient.rejectAIPlan(plan.id)
        }
        pendingHighRiskPlan = nil
        await loadHistory()
    }

    // MARK: - Rollback (history rows for already-executed plans)

    @discardableResult
    func rollback(_ actionID: String) async -> Bool {
        do {
            actionError = nil
            _ = try await apiClient.rollbackAIAction(actionID)
            await loadHistory()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    private func firstValidationError(accounts: [AccountDTO], categories: [CategoryDTO]) -> String? {
        for action in editableActions {
            if let error = action.validationError(accounts: accounts, categories: categories) {
                return error
            }
        }
        return nil
    }
}
