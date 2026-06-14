#if os(macOS)
import AppKit
import SwiftUI

// MenuBarPopover — Py ⑥ macOS MenuBarExtra (window style).
//
// v2 reimplementation of v1's `Platform/macOS/MenuBarPopover`: 4 metric rows
// (未来一月可支配 / 美元余额 / 下次还款 / AI 待确认) + 快速记账 / 同步 pills + a
// host/version footer. Reads `AppModel` directly (v1 read `AppEnvironment`'s
// ViewModels). Styled with the v2 glass tokens.
//
// Requires `.menuBarExtraStyle(.window)` on the MenuBarExtra scene, otherwise the
// default `.menu` style breaks the custom layout.
struct MenuBarPopover: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LinoFinance")
                .font(Theme.Font.subtitle(.semibold))
                .foregroundStyle(Theme.Color.textPrimary)

            VStack(spacing: 7) {
                MenuBarRow(
                    label: "未来一月可支配",
                    value: FinanceFormatter.money(model.disposable30dCny),
                    tint: Theme.Color.income
                )
                MenuBarRow(
                    label: "美元余额",
                    value: FinanceFormatter.money(model.usdBalanceTotal, currency: .usd),
                    tint: model.usdBalanceTotal.value > 0 ? Theme.Color.usd : Theme.Color.textSecondary
                )
                MenuBarRow(
                    label: "下次还款",
                    value: nextCreditDueText,
                    tint: model.nextCreditCycle == nil ? Theme.Color.textSecondary : Theme.Color.expense
                )
                MenuBarRow(
                    label: "AI 待确认",
                    value: model.pendingAIPlans.isEmpty ? "无" : "\(model.pendingAIPlans.count) 个计划",
                    tint: model.pendingAIPlans.isEmpty ? Theme.Color.textSecondary : Theme.Color.link
                )
            }

            HStack(spacing: 6) {
                MenuBarPillButton(title: "快速记账", systemImage: "plus") {
                    // Bring the app forward so the 记一笔 page comes up key, then
                    // route to the AddEntry page (same path as ⌘N).
                    NSApp.activate(ignoringOtherApps: true)
                    model.isAddEntryPresented = true
                }
                MenuBarPillButton(title: "同步", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.refreshAll() }
                }
            }
            .padding(.top, 2)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.dashboard == nil ? Theme.Color.expense : Theme.Color.income)
                    .frame(width: 6, height: 6)
                Text(model.baseURL.host ?? model.baseURL.absoluteString)
                    .font(Theme.Font.badge().monospacedDigit())
                    .foregroundStyle(Theme.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(appVersionLabel)
                    .font(Theme.Font.badge().monospacedDigit())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 260)
        .task {
            await model.refreshAll()
        }
    }

    private var nextCreditDueText: String {
        guard let cycle = model.nextCreditCycle else { return "无待还款" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: cycle.dueDate).day ?? 0
        return "\(days) 天 · \(FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency))"
    }

    private var appVersionLabel: String {
        let bundleVersion = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let bundleVersion, !bundleVersion.isEmpty {
            return "v\(bundleVersion)"
        }
        return "v?"
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
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.Font.caption(.medium).monospacedDigit())
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
            .foregroundStyle(Theme.Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(Theme.Color.glassFill.opacity(isHovering ? 1 : 0.7))
                    .overlay {
                        Capsule().strokeBorder(Theme.Color.glassStroke, lineWidth: 0.5)
                    }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
#endif
