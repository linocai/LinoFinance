import SwiftUI

#if os(macOS)

// CashFlowScreen — D4 现金流 (macOS, liquid glass). R2 redesign (Phase A).
//
// Comp source: lf_cashflow.png / lf_chips.png — a single glass card of hairline-
// divided rows; each row = 图标 + 标题 + status/type tags + dual-currency amount +
// inline soft action chips on the right. The old `⋯ Menu` + native二次确认 `.alert`
// are GONE (user disliked the生硬的原生弹窗): each `TintedActionChip` fires its
// action DIRECTLY.
//   确认 (positive/绿) → confirm
//   兑现 (action/蓝)   → settle (one-shot if linked, else SettleCompletionSheet)
//   取消 (neutral/灰)  → cancel (comp uses gray; destructive semantics retained
//                        only by the model call, no red per comp)
// Transfers / reimbursement-linked rows hide 兑现 (their own flows settle them) —
// the existing `canShowSettleAction` gate is unchanged.
//
// `actionError` banner stays (glass). The 新建现金流 button is now a
// SubtleToolbarButton. SettleCompletionSheet is kept for the missing-link edge
// case, re-skinned with R0 controls.
//
// Contract: `init(model: AppModel)`; owns its own @StateObject CashFlowModel.

struct CashFlowScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var cashFlowModel: CashFlowModel

    @State private var formMode: CashFlowFormSheet.Mode?
    @State private var settleItem: CashFlowItemDTO?
    @State private var repaymentItem: CashFlowItemDTO?

    init(model: AppModel) {
        self.model = model
        _cashFlowModel = StateObject(wrappedValue: CashFlowModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            actionBanner

            switch cashFlowModel.state {
            case .idle, .loading where cashFlowModel.items.isEmpty:
                loadingState
            case .failed(let message):
                failedState(message)
            default:
                content
            }
        }
        .task { if cashFlowModel.items.isEmpty { await cashFlowModel.load() } }
        .sheet(item: $formMode) { mode in
            CashFlowFormSheet(model: cashFlowModel, mode: mode) {}
        }
        .sheet(item: $settleItem) { item in
            SettleCompletionSheet(model: cashFlowModel, item: item) {}
        }
        .sheet(item: $repaymentItem) { item in
            RepaymentConfirmSheet(model: cashFlowModel, item: item) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("现金流")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("未来预计收支 · 确认 / 兑现 / 取消")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            SubtleToolbarButton(title: "新建现金流") { formMode = .create }
        }
    }

    @ViewBuilder
    private var actionBanner: some View {
        if let message = cashFlowModel.actionError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer(minLength: 8)
                Button {
                    cashFlowModel.actionError = nil
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            .padding(12)
            .glassPanel(cornerRadius: Theme.Radius.button, tint: Theme.Color.expense)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if cashFlowModel.items.isEmpty {
            emptyState
        } else {
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(cashFlowModel.sortedItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.Color.divider) }
                        CashFlowRow(
                            item: item,
                            accountName: cashFlowModel.accountName(item.accountId),
                            actions: rowActions(for: item)
                        )
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private func rowActions(for item: CashFlowItemDTO) -> CashFlowRowActions {
        let actionable = item.status == "expected" || item.status == "confirmed"
        return CashFlowRowActions(
            canEdit: actionable,
            canConfirm: actionable && item.status == "expected",
            canSettle: actionable && item.canShowSettleAction,
            settleTitle: item.direction == "transfer" ? "确认还款" : "兑现",
            canCancel: actionable,
            edit: { formMode = .edit(item) },
            confirm: { Task { await cashFlowModel.confirm(item.id) } },
            settle: { settle(item) },
            cancel: { Task { await cashFlowModel.cancel(item.id) } }
        )
    }

    // MARK: - Actions (no native confirm dialog — chips fire directly, R2)

    private func settle(_ item: CashFlowItemDTO) {
        Task {
            switch await cashFlowModel.attemptSettle(item) {
            case .needsCompletion:
                settleItem = item
            case .needsRepaymentSource:
                repaymentItem = item
            case .blocked(let message):
                cashFlowModel.actionError = message
            case .settled:
                break
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("还没有现金流")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("创建一次性或周期性的预计收支后，这里会列出未来事件。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                SubtleToolbarButton(title: "新建现金流") { formMode = .create }
                    .padding(.top, 4)
            }
        }
    }

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载现金流…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("现金流加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                SubtleToolbarButton(title: "重试", systemImage: "arrow.clockwise") {
                    Task { await cashFlowModel.load() }
                }
            }
        }
    }
}

// MARK: - Row

struct CashFlowRowActions {
    var canEdit: Bool
    var canConfirm: Bool
    var canSettle: Bool
    /// Settle chip label — "确认还款" for transfers (信用还款), "兑现" otherwise.
    var settleTitle: String = "兑现"
    var canCancel: Bool
    var edit: () -> Void
    var confirm: () -> Void
    var settle: () -> Void
    var cancel: () -> Void
}

private struct CashFlowRow: View {
    let item: CashFlowItemDTO
    let accountName: String?
    let actions: CashFlowRowActions

    private var isSettled: Bool { item.status == "settled" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: directionSymbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    StatusBadge(text: item.statusTitle, tone: item.statusTone)
                    StatusBadge(text: CashFlowType.title(item.cashFlowType), tone: .neutral)
                }
                Text(subtitle)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            AmountText(value: item.amount, currency: item.currency,
                       font: Theme.Font.subtitle(.semibold), color: tint)
            actionChips
        }
        .opacity(isSettled ? 0.55 : 1)
    }

    // Inline soft action chips (R2) — direct-fire, no menu / no confirm dialog.
    @ViewBuilder
    private var actionChips: some View {
        HStack(spacing: 8) {
            if actions.canConfirm {
                TintedActionChip(title: "确认", tone: .positive, action: actions.confirm)
            }
            if actions.canSettle {
                TintedActionChip(title: actions.settleTitle, tone: .action, action: actions.settle)
            }
            if actions.canCancel {
                TintedActionChip(title: "取消", tone: .neutral, action: actions.cancel)
            }
        }
        .fixedSize()
    }

    private var subtitle: String {
        "\(Self.dateText(item.expectedDate)) · \(accountName ?? "未关联账户")"
    }

    private var directionSymbol: String {
        switch item.direction {
        case "inflow": "arrow.down.circle.fill"
        case "outflow": "arrow.up.circle.fill"
        default: "arrow.left.arrow.right.circle.fill"
        }
    }

    private var tint: Color {
        if isSettled { return Theme.Color.textTertiary }
        switch item.direction {
        case "inflow": return Theme.Color.income
        case "outflow": return Theme.Color.expense
        default: return Theme.Color.textSecondary
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f
    }()

    private static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }
}

#endif
