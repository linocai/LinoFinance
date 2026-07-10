import SwiftUI

#if os(macOS)

// AIScreen — v3.0.0 P4 ① 独立 AI 屏 (macOS 侧栏, D5=乙).
//
// 自然语言输入 → 提案确认 (明细可展开、可改账户分类 — id 映射安全网) → 执行；下方是
// 近期提案历史 (非终态可再次打开编辑续跑同一套确认流，已执行的可回滚)。原本挤在
// Settings 第 7 节「AI 助手」卡里的自然语言输入框 + 提案列表就是搬到这里；AI 连接
// 配置 (base_url/key/model) 仍留在 Settings，见 `AIConfigFormCard`。
struct AIScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var ai: AIAssistantModel

    init(model: AppModel) {
        self.model = model
        _ai = StateObject(wrappedValue: AIAssistantModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if ai.configState == .loaded && !ai.isConfigured {
                notConfiguredBanner
            }
            inputCard
            if ai.hasDraft {
                AIPlanReviewPanel(
                    ai: ai,
                    accounts: model.accounts,
                    categories: model.categories,
                    onLedgerChanged: { await model.refreshAll() }
                )
            }
            historySection
        }
        .task {
            await ai.loadConfigStatus()
            if model.accounts.isEmpty { await model.loadAccounts() }
            if model.categories.isEmpty { await model.loadCategories() }
            if ai.history.isEmpty { await ai.loadHistory() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("AI")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("自然语言记账 · 执行前逐条核对账户与分类")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            SubtleToolbarButton(title: "刷新历史", systemImage: "arrow.clockwise") {
                Task { await ai.loadHistory() }
            }
        }
    }

    private var notConfiguredBanner: some View {
        GlassCard(tint: Theme.fixed(0xE08A1F)) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.fixed(0xE08A1F))
                VStack(alignment: .leading, spacing: 2) {
                    Text("还没有配置 AI")
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("请到设置填写 AI 的 Base URL / API Key / Model。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
                TintedActionChip(title: "去设置", systemImage: "arrow.up.right", tone: .action) {
                    model.selection = .settings
                }
            }
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("说说发生了什么")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                TextEditor(text: $ai.sourceText)
                    .font(Theme.Font.body())
                    .scrollContentBackground(.hidden)
                    .frame(height: 84)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassPanel(cornerRadius: Theme.Radius.button)
                    .overlay(alignment: .topLeading) {
                        if ai.sourceText.isEmpty {
                            Text("例如：昨天在星巴克花了 38 元，用招商卡")
                                .font(Theme.Font.body())
                                .foregroundStyle(Theme.Color.textTertiary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                if let error = ai.actionError, !ai.hasDraft {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.expense)
                        .lineLimit(3)
                }
                HStack {
                    Spacer()
                    PrimaryDarkButton("解析", isLoading: ai.isParsing) {
                        Task { await ai.submitSourceText() }
                    }
                    .disabled(ai.isParsing || ai.sourceText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity((ai.isParsing || ai.sourceText.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.5 : 1)
                }
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("近期提案")
                .font(Theme.Font.subtitle(.semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            switch ai.historyState {
            case .idle, .loading:
                GlassCard {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("加载中…").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            case .failed(let message):
                GlassCard {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.expense)
                }
            case .loaded:
                if ai.history.isEmpty {
                    GlassCard {
                        Text("还没有 AI 提案。上面写一句话试试。")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                } else {
                    ForEach(ai.history) { plan in
                        AIPlanHistoryRow(
                            plan: plan,
                            onOpen: { ai.openForEdit(plan) },
                            onRollback: { actionID in
                                Task {
                                    let ok = await ai.rollback(actionID)
                                    if ok { await model.refreshAll() }
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

#endif
