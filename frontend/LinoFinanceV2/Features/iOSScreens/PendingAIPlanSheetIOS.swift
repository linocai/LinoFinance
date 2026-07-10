import SwiftUI

#if os(iOS)

// PendingAIPlanSheetIOS — v3.1.0 P3 iOS AI 提案呈现 (深链/通知落点).
//
// Reached from `AppModel.pendingAIPlanId`, set by `handlePushNotificationTarget`
// for the `ai_plan` target — the SAME setter fires whether that target arrived
// via a remote push or a local notification tap (`LocalNotifications`), since
// both carry the identical `target_type`/`target_id` userInfo shape (D5 甲).
//
// Unlike `AIProposalSheetIOS` (natural-language text → a NEW plan), this loads
// an EXISTING plan by id (`GET /ai/plans/{plan_id}`) and either renders the
// exact same `AIPlanReviewPanel` the rest of the app already uses (via
// `AIAssistantModel.openForEdit` — zero new review UI) when the plan is still
// actionable, or a plain "already handled" card when it has reached a terminal
// status. `reviewableStatuses` mirrors `AIPlanHistoryRow.isReviewable`'s exact
// status set so "can I still act on this" never diverges between the history
// list and this deep-link landing.
struct PendingAIPlanSheetIOS: View {
    @ObservedObject var model: AppModel
    let planId: String
    /// Called after a successful execute/reject/cancel — mirrors
    /// `AIProposalSheetIOS.onExecuted`. AppModel is already refreshed by the
    /// time this fires.
    var onFinished: () -> Void

    @StateObject private var ai: AIAssistantModel
    @Environment(\.dismiss) private var dismiss

    private enum LoadState: Equatable {
        case loading
        case notFound(String)
        case ready(AIPlanDTO)
    }
    @State private var loadState: LoadState = .loading

    /// Same set `AIPlanHistoryRow.isReviewable` uses — anything outside it
    /// (`executed` / `rejected` / `cancelled` / `rolled_back`) is terminal.
    private static let reviewableStatuses: Set<String> = [
        "requires_confirmation", "auto_confirm_candidate", "approved", "failed", "pending",
    ]

    init(model: AppModel, planId: String, onFinished: @escaping () -> Void) {
        self.model = model
        self.planId = planId
        self.onFinished = onFinished
        _ai = StateObject(wrappedValue: AIAssistantModel(apiClient: model.apiClient))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BloomBackground(animated: false).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .padding(16)
                }
            }
            .navigationTitle("AI 提案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            if model.accounts.isEmpty { await model.loadAccounts() }
            if model.categories.isEmpty { await model.loadCategories() }
            await load()
        }
        // Reject/cancel inside AIPlanReviewPanel clear `ai.hasDraft` but don't
        // call `onLedgerChanged` (that only fires on a successful execute) —
        // without this the sheet would sit on a now-blank panel until the
        // user manually taps 关闭. Guarded by `wasLoaded` so it never fires
        // during the initial loading→ready transition.
        .onChange(of: ai.hasDraft) { wasLoaded, isLoaded in
            if wasLoaded, !isLoaded {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            GlassCard {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("加载提案中…").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                }
            }
        case .notFound(let message):
            GlassCard {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
            }
        case .ready(let plan):
            if Self.reviewableStatuses.contains(plan.status), ai.hasDraft {
                AIPlanReviewPanel(
                    ai: ai,
                    accounts: model.accounts,
                    categories: model.categories,
                    onLedgerChanged: {
                        await model.refreshAll()
                        onFinished()
                        dismiss()
                    }
                )
            } else {
                alreadyHandledCard(plan)
            }
        }
    }

    private func alreadyHandledCard(_ plan: AIPlanDTO) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("这条提案已处理", systemImage: "checkmark.circle.fill")
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("状态：\(plan.status.financeStatusTitle)")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                if !plan.sourceText.isEmpty {
                    Text("“\(plan.sourceText)”")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(3)
                }
            }
        }
    }

    private func load() async {
        loadState = .loading
        do {
            // Matches `AIAssistantModel`'s own convention of calling
            // `apiClient` directly for every AI-plan operation (never
            // `AppModel`'s cached-resource wrapper methods) — this sheet is
            // scoped to one plan the same way that model is.
            let plan = try await model.apiClient.aiPlan(planId)
            if Self.reviewableStatuses.contains(plan.status) {
                ai.openForEdit(plan)
            }
            loadState = .ready(plan)
        } catch {
            loadState = .notFound("没有找到这条提案：\(error.localizedDescription)")
        }
    }
}

#endif
