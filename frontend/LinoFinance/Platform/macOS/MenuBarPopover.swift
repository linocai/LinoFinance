#if os(macOS)
import SwiftUI

/// macOS 菜单栏弹窗 —— 对齐 HTML 第 1498-1518 行 `.menubar-extra`：
/// title + 4 metric rows（label 左 / value 右 mono + 语义着色）+ 3 pill action 按钮 + footer。
/// 需要在 LinoFinanceApp 里给 MenuBarExtra 设 `.menuBarExtraStyle(.window)`，
/// 否则默认 `.menu` 风格会破坏自定义版式。
struct MenuBarPopover: View {
    @Bindable var environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    private var nextCreditDue: CreditStatementCycleDTO? {
        environment.creditViewModel.cycles
            .filter { $0.status != "paid" && $0.status != "closed" }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    private var pendingAIPlans: [AIPlanDTO] {
        environment.aiViewModel.plans.filter {
            ["requires_confirmation", "auto_confirm_candidate", "failed"].contains($0.status)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LinoFinance")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FinanceTokens.Text.primary)

            VStack(spacing: 7) {
                MenuBarRow(
                    label: "净资产",
                    value: FinanceFormatter.money(environment.dashboardViewModel.summary?.netWorthCny ?? DecimalValue(0)),
                    tint: FinanceTokens.Text.primary
                )
                MenuBarRow(
                    label: "今日新增",
                    value: "\(todayEntryCount) 笔",
                    tint: todayEntryCount > 0 ? FinanceTokens.State.income : FinanceTokens.Text.secondary
                )
                MenuBarRow(
                    label: "下次还款",
                    value: nextCreditDueText,
                    tint: nextCreditDue == nil ? FinanceTokens.Text.secondary : FinanceTokens.State.credit
                )
                MenuBarRow(
                    label: "AI 待确认",
                    value: pendingAIPlans.isEmpty ? "无" : "\(pendingAIPlans.count) 个计划",
                    tint: pendingAIPlans.isEmpty ? FinanceTokens.Text.secondary : FinanceTokens.State.ai
                )
            }

            HStack(spacing: 6) {
                MenuBarPillButton(title: "快速记账", systemImage: "plus") {
                    openWindow(id: "command")
                }
                MenuBarPillButton(title: "同步", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await environment.refreshPrimaryData() }
                }
                MenuBarPillButton(title: "⌘K", systemImage: "wand.and.stars") {
                    openWindow(id: "command")
                }
            }
            .padding(.top, 2)

            HStack(spacing: 6) {
                Circle()
                    .fill(environment.lastErrorMessage == nil ? FinanceTokens.State.income : FinanceTokens.State.warning)
                    .frame(width: 6, height: 6)
                Text(environment.apiClient.baseURL.host ?? environment.apiClient.baseURL.absoluteString)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("v1.1.0")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.tertiary)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 260)
        .task {
            await environment.refreshPrimaryData()
        }
    }

    private var todayEntryCount: Int {
        let calendar = Calendar.current
        return environment.entriesViewModel.entries.filter {
            calendar.isDateInToday($0.date)
        }.count
    }

    private var nextCreditDueText: String {
        guard let cycle = nextCreditDue else { return "无待还款" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: cycle.dueDate).day ?? 0
        return "\(days) 天 · \(FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency))"
    }
}

// MARK: - Row

private struct MenuBarRow: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(FinanceTokens.Text.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}

// MARK: - Pill button

private struct MenuBarPillButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(FinanceTokens.Text.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(isHovering ? FinanceTokens.Surface.glassStrong : FinanceTokens.Surface.glass)
                    .overlay {
                        Capsule().stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                    }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
#endif
