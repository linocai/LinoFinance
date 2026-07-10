import SwiftUI

#if os(iOS)

// AIProposalSheetIOS — v3.0.0 P4 ① iOS「AI 解析」入口 (记一笔 sheet 内, D5).
//
// 极简版：一句话 → 解析出提案 → 同款明细确认卡 (可展开、可改账户分类 — 与 macOS
// AIScreen 共用 `AIPlanReviewPanel`/`AIActionCard`)。不做历史列表 (那是 macOS
// 独有，iOS 保持极简，per plan)。执行成功后关闭自己 + 通知宿主 (记一笔 sheet)
// 一并关闭并刷新。
struct AIProposalSheetIOS: View {
    @ObservedObject var model: AppModel
    /// Called after a successful execute — the caller closes the outer 记一笔
    /// sheet and refreshes (AppModel itself is already refreshed by the time
    /// this fires, via `onLedgerChanged` below).
    var onExecuted: () -> Void

    @StateObject private var ai: AIAssistantModel
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, onExecuted: @escaping () -> Void) {
        self.model = model
        self.onExecuted = onExecuted
        _ai = StateObject(wrappedValue: AIAssistantModel(apiClient: model.apiClient))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BloomBackground(animated: false).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if ai.configState == .loaded && !ai.isConfigured {
                            notConfiguredBanner
                        }
                        inputCard
                        if ai.hasDraft {
                            AIPlanReviewPanel(
                                ai: ai,
                                accounts: model.accounts,
                                categories: model.categories,
                                onLedgerChanged: {
                                    await model.refreshAll()
                                    onExecuted()
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("AI 解析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            await ai.loadConfigStatus()
            if model.accounts.isEmpty { await model.loadAccounts() }
            if model.categories.isEmpty { await model.loadCategories() }
        }
    }

    private var notConfiguredBanner: some View {
        GlassCard(tint: Theme.fixed(0xE08A1F)) {
            VStack(alignment: .leading, spacing: 6) {
                Label("还没有配置 AI", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("请到「更多 → 设置」填写 Base URL / API Key / Model。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private var inputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("说说发生了什么")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                TextEditor(text: $ai.sourceText)
                    .font(Theme.Font.body())
                    .scrollContentBackground(.hidden)
                    .frame(height: 100)
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
}

#endif
