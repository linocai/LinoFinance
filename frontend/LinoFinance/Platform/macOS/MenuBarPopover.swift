#if os(macOS)
import SwiftUI

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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LinoF")
                        .font(FinanceTypography.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                    PrivacyAmount(
                        value: FinanceFormatter.money(environment.dashboardViewModel.summary?.netWorthCny ?? DecimalValue(0)),
                        font: .title2.weight(.semibold).monospacedDigit()
                    )
                }
                Spacer()
                Button {
                    Task { await environment.refreshPrimaryData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("同步")
            }

            VStack(spacing: 8) {
                MenuBarMetric(
                    title: "今日新增",
                    value: "\(todayEntryCount) 笔",
                    systemImage: "calendar.badge.plus"
                )
                MenuBarMetric(
                    title: "下次还款",
                    value: nextCreditDue.map { FinanceFormatter.mediumDate($0.dueDate) } ?? "无待还款",
                    systemImage: "creditcard"
                )
                MenuBarMetric(
                    title: "AI 待确认",
                    value: "\(pendingAIPlans.count)",
                    systemImage: "sparkles"
                )
            }

            Divider()

            Button {
                environment.beginNewEntry()
                openWindow(id: "main")
            } label: {
                Label("快速记账", systemImage: "plus.circle.fill")
            }

            Button {
                Task { await environment.refreshPrimaryData() }
            } label: {
                Label("同步", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                openWindow(id: "command")
            } label: {
                Label("打开 ⌘K", systemImage: "command")
            }

            Divider()

            Label("菜单栏入口已固定显示", systemImage: "pin.fill")
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
        .padding(14)
        .frame(width: 280)
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
}

private struct MenuBarMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(FinanceTokens.Brand.primary)
                .frame(width: 20)
            Text(title)
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
            Spacer()
            Text(value)
                .font(FinanceTypography.bodyMono)
                .foregroundStyle(FinanceTokens.Text.primary)
        }
    }
}
#endif
