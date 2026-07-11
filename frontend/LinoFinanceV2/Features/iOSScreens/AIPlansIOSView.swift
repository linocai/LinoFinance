import SwiftUI

#if os(iOS)

// AIPlansIOSView — iOS「AI 提案」列表（更多 → AI 提案）。
//
// 真机反馈驱动（2026-07-11）：免提录入产生的「待确认提案」此前在 iOS 上只有
// 通知这一个入口——通知一划掉，app 里就没有任何地方能找到它（macOS 有 AI 屏
// 历史，iOS 极简版没做）。本屏补上这个缺口：待处理的提案排前、可点开确认
//（复用 `PendingAIPlanSheetIOS` → `AIPlanReviewPanel`，零新审阅 UI），最近
// 已处理的列后面供核对。
struct AIPlansIOSView: View {
    @ObservedObject var model: AppModel

    private enum LoadState: Equatable {
        case loading
        case failed(String)
        case loaded
    }

    @State private var loadState: LoadState = .loading
    @State private var plans: [AIPlanDTO] = []
    @State private var reviewingPlanId: String?

    /// 与 `AIPlanHistoryRow.isReviewable` / `PendingAIPlanSheetIOS` 同一套口径。
    private static let actionableStatuses: Set<String> = [
        "requires_confirmation", "auto_confirm_candidate", "approved", "failed", "pending",
    ]

    private var actionable: [AIPlanDTO] {
        plans.filter { Self.actionableStatuses.contains($0.status) }
    }

    private var recentHandled: [AIPlanDTO] {
        Array(plans.filter { !Self.actionableStatuses.contains($0.status) }.prefix(10))
    }

    var body: some View {
        ZStack {
            BloomBackground(animated: false).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("AI 提案")
        .task { await load() }
        .sheet(isPresented: Binding(
            get: { reviewingPlanId != nil },
            set: { if !$0 { reviewingPlanId = nil } }
        )) {
            if let planId = reviewingPlanId {
                PendingAIPlanSheetIOS(model: model, planId: planId) {
                    Task { await load() }
                }
                .onDisappear { Task { await load() } }
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
                    Text("加载提案中…")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        case .failed(let message):
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("提案加载失败", systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.caption(.semibold))
                        .foregroundStyle(Theme.Color.expense)
                    Text(message)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                    SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                }
            }
        case .loaded:
            if actionable.isEmpty && recentHandled.isEmpty {
                GlassCard {
                    Text("还没有 AI 提案。用「嘿 Siri，用 LinoF AI 记一笔」或截图敲三下试试。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            if !actionable.isEmpty {
                sectionTitle("待处理（\(actionable.count)）")
                ForEach(actionable) { plan in
                    planCard(plan, actionable: true)
                }
            }
            if !recentHandled.isEmpty {
                sectionTitle("最近已处理")
                ForEach(recentHandled) { plan in
                    planCard(plan, actionable: false)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption(.semibold))
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.horizontal, 4)
    }

    private func planCard(_ plan: AIPlanDTO, actionable: Bool) -> some View {
        Button {
            if actionable { reviewingPlanId = plan.id }
        } label: {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(planTitle(plan))
                            .font(Theme.Font.body(.semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        StatusBadge(text: plan.status.financeStatusTitle, tone: actionable ? .warning : .neutral)
                    }
                    HStack(spacing: 8) {
                        Text(plan.riskLevel.financeStatusTitle)
                            .font(Theme.Font.badge())
                            .foregroundStyle(Theme.Color.textTertiary)
                        Spacer(minLength: 8)
                        if actionable {
                            HStack(spacing: 3) {
                                Text("去确认")
                                Image(systemName: "chevron.right")
                            }
                            .font(Theme.Font.badge(.medium))
                            .foregroundStyle(Theme.Color.brandEnd)
                        }
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!actionable)
    }

    private func planTitle(_ plan: AIPlanDTO) -> String {
        let source = plan.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if !source.isEmpty { return source }
        return plan.explanation ?? "AI 提案"
    }

    private func load() async {
        if plans.isEmpty { loadState = .loading }
        do {
            plans = try await model.apiClient.listAIPlans()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

#endif
