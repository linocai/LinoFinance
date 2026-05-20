import SwiftUI

struct AIWorkspaceView: View {
    @Bindable var environment: AppEnvironment
    @State private var prompt = ""
    @State private var strongConfirm = ""
    @State private var confirmation: ConfirmAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "AI", subtitle: "计划、确认、执行与回滚")

            if let config = environment.aiViewModel.config {
                LazyVGrid(columns: aiConfigColumns, spacing: 12) {
                    ToolbarPill(title: "Provider", value: config.provider, tint: FinanceTokens.State.ai)
                    ToolbarPill(title: "模型", value: config.model ?? "未配置", tint: FinanceTokens.State.ai)
                    ToolbarPill(title: "API Key", value: config.apiKeyConfigured ? "已配置" : "未配置", tint: config.apiKeyConfigured ? FinanceTokens.State.income : FinanceTokens.State.warning)
                    ToolbarPill(title: "自动确认阈值", value: FinanceFormatter.money(config.autoConfirmLimitCny), tint: FinanceTokens.Brand.primary)
                }
            }

            FinancePanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("一句话创建 AI 计划")
                        .font(.headline)
                    TextField("例如：今天午餐 88 元，从招商银行支出，分类餐饮", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            strongConfirmField
                            Spacer()
                            createPlanButton
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            strongConfirmField
                            createPlanButton
                        }
                    }
                }
            }

            if environment.aiViewModel.plans.isEmpty {
                EmptyState(title: "还没有 AI 计划", message: "输入自然语言后，后端会生成结构化动作卡。", systemImage: "sparkles")
            } else {
                List(environment.aiViewModel.plans, selection: Binding(
                    get: {
                        if case .aiPlan(let plan) = environment.inspectorSelection {
                            return plan.id
                        }
                        return nil
                    },
                    set: { id in
                        guard let id, let plan = environment.aiViewModel.plans.first(where: { $0.id == id }) else { return }
                        environment.inspectorSelection = .aiPlan(plan)
                    }
                )) { plan in
                    AIPlanCard(plan: plan, strongConfirm: strongConfirm, action: confirm)
                        .tag(plan.id)
                        .contentShape(Rectangle())
                        .onTapGesture { environment.inspectorSelection = .aiPlan(plan) }
                }
                .listStyle(.inset)
            }

            if let message = environment.aiViewModel.errorMessage {
                ErrorBanner(message: message)
            }
        }
        .padding(FinanceTokens.Spacing.page)
        .moduleFrame()
        .task {
            try? await environment.aiViewModel.refresh()
        }
        .alert(confirmation?.title ?? "确认操作", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), presenting: confirmation) { item in
            Button(item.confirmTitle, role: item.role) {
                item.action()
                confirmation = nil
            }
            Button("取消", role: .cancel) { confirmation = nil }
        } message: { item in
            Text(item.message)
        }
    }

    private var aiConfigColumns: [GridItem] {
#if os(iOS)
        [GridItem(.adaptive(minimum: 140), spacing: 12)]
#else
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
#endif
    }

    private var strongConfirmField: some View {
        TextField("高风险强确认：EXECUTE_HIGH_RISK", text: $strongConfirm)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 280)
    }

    private var createPlanButton: some View {
        Button {
            Task { await createPlan() }
        } label: {
            Label("生成计划", systemImage: "sparkles")
        }
        .buttonStyle(.borderedProminent)
        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func createPlan() async {
        do {
            try await environment.aiViewModel.createPlan(sourceText: prompt.trimmingCharacters(in: .whitespacesAndNewlines))
            prompt = ""
        } catch {
            environment.aiViewModel.errorMessage = error.localizedDescription
        }
    }

    private func confirm(_ plan: AIPlanDTO, _ operation: String, _ actionID: String?) {
        let title: String
        let message: String
        let button: String
        let role: ButtonRole?
        switch operation {
        case "approve":
            title = "批准 AI 计划？"
            message = "批准后仍需手动执行。"
            button = "批准"
            role = nil
        case "reject":
            title = "拒绝 AI 计划？"
            message = "待处理动作会被跳过。"
            button = "拒绝"
            role = .destructive
        case "execute":
            title = "执行 AI 计划？"
            message = plan.riskLevel == "high" ? "高风险计划必须输入 EXECUTE_HIGH_RISK，执行会写审计日志。" : "执行会创建或修改财务对象，并写审计日志。"
            button = "执行"
            role = plan.riskLevel == "high" ? .destructive : nil
        default:
            title = "回滚 AI 动作？"
            message = "仅已执行且后端支持的动作可回滚，回滚同样会写审计日志。"
            button = "回滚"
            role = .destructive
        }
        confirmation = ConfirmAction(title: title, message: message, confirmTitle: button, role: role) {
            Task { await perform(plan, operation, actionID) }
        }
    }

    private func perform(_ plan: AIPlanDTO, _ operation: String, _ actionID: String?) async {
        do {
            switch operation {
            case "approve":
                try await environment.aiViewModel.approve(plan.id)
            case "reject":
                try await environment.aiViewModel.reject(plan.id)
            case "execute":
                let confirm = plan.riskLevel == "high" ? strongConfirm : nil
                try await environment.aiViewModel.execute(plan.id, strongConfirm: confirm)
                await environment.refreshPrimaryData()
            default:
                if let actionID {
                    try await environment.aiViewModel.rollbackAction(actionID)
                    await environment.refreshPrimaryData()
                }
            }
        } catch {
            environment.aiViewModel.errorMessage = error.localizedDescription
        }
    }
}

private struct AIPlanCard: View {
    let plan: AIPlanDTO
    let strongConfirm: String
    let action: (AIPlanDTO, String, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    planSummary
                    Spacer()
                    StatusTag(status: plan.riskLevel)
                    StatusTag(status: plan.status)
                }

                VStack(alignment: .leading, spacing: 8) {
                    planSummary
                    HStack {
                        StatusTag(status: plan.riskLevel)
                        StatusTag(status: plan.status)
                    }
                }
            }

            ForEach(plan.actions) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.actionType)
                            .font(.subheadline.weight(.semibold))
                        Text(item.explanation ?? item.payload.map { "\($0.key)=\($0.value.displayText)" }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(FinanceTokens.Text.secondary)
                            .lineLimit(3)
                    }
                    Spacer()
                    StatusTag(status: item.status)
                    if item.status == "executed" {
                        Button("回滚") { action(plan, "rollback", item.id) }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(10)
                .background(FinanceTokens.Stroke.soft.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("批准") { action(plan, "approve", nil) }
                    .disabled(["approved", "executed", "rejected"].contains(plan.status))
                Button("拒绝", role: .destructive) { action(plan, "reject", nil) }
                    .disabled(["executed", "rejected"].contains(plan.status))
                Spacer()
                Button("执行") { action(plan, "execute", nil) }
                    .buttonStyle(.borderedProminent)
                    .disabled(plan.riskLevel == "high" && strongConfirm != "EXECUTE_HIGH_RISK")
            }
        }
        .padding(.vertical, 8)
    }

    private var planSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.sourceText)
                .font(.headline)
                .lineLimit(2)
            Text(plan.explanation ?? "结构化动作计划")
                .font(.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
                .lineLimit(3)
        }
    }

}
