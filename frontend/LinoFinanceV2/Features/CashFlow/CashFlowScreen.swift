import SwiftUI

#if os(macOS)

// CashFlowScreen — D4 现金流 (macOS, liquid glass). Replaces the P2 stub.
//
// Lists future expected income/expense (cancelled hidden) as glass rows with a
// status badge + dual-currency original amount. Each active row carries three
// actions wired to distinct endpoints: 确认 (confirm) / 兑现 (settle) / 取消
// (cancel). 兑现 either settles directly (account+category already linked) or
// opens SettleCompletionSheet to gather them first. Transfers and
// reimbursement-linked rows hide the 兑现 entry (their own flows settle them).
//
// Contract: `init(model: AppModel)`; owns its own @StateObject CashFlowModel.

struct CashFlowScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var cashFlowModel: CashFlowModel

    @State private var formMode: CashFlowFormSheet.Mode?
    @State private var settleItem: CashFlowItemDTO?
    @State private var confirmDialog: ConfirmDialog?

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
        .alert(confirmDialog?.title ?? "", isPresented: Binding(
            get: { confirmDialog != nil },
            set: { if !$0 { confirmDialog = nil } }
        ), presenting: confirmDialog) { dialog in
            Button(dialog.confirmTitle, role: dialog.destructive ? .destructive : nil) {
                dialog.action()
                confirmDialog = nil
            }
            Button("取消", role: .cancel) { confirmDialog = nil }
        } message: { dialog in
            Text(dialog.message)
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
            Button {
                formMode = .create
            } label: {
                Label("新建现金流", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
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
            canCancel: actionable,
            edit: { formMode = .edit(item) },
            confirm: { Task { await cashFlowModel.confirm(item.id) } },
            settle: { settle(item) },
            cancel: { cancel(item) }
        )
    }

    // MARK: - Actions

    private func settle(_ item: CashFlowItemDTO) {
        confirmDialog = ConfirmDialog(
            title: "兑现为正式记录？",
            message: "这会创建一条正式记账记录，并影响账户余额。",
            confirmTitle: "兑现",
            destructive: false
        ) {
            Task {
                switch await cashFlowModel.attemptSettle(item) {
                case .needsCompletion:
                    settleItem = item
                case .blocked(let message):
                    cashFlowModel.actionError = message
                case .settled:
                    break
                }
            }
        }
    }

    private func cancel(_ item: CashFlowItemDTO) {
        confirmDialog = ConfirmDialog(
            title: "取消现金流？",
            message: "取消后此现金流不再计入未来压力。",
            confirmTitle: "取消现金流",
            destructive: true
        ) {
            Task { await cashFlowModel.cancel(item.id) }
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
                Button("新建现金流") { formMode = .create }
                    .buttonStyle(.borderedProminent)
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
                Button("重试") { Task { await cashFlowModel.load() } }
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Row

struct CashFlowRowActions {
    var canEdit: Bool
    var canConfirm: Bool
    var canSettle: Bool
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
            actionMenu
        }
        .opacity(isSettled ? 0.55 : 1)
    }

    private var actionMenu: some View {
        Menu {
            if actions.canEdit { Button("编辑") { actions.edit() } }
            if actions.canConfirm { Button("确认") { actions.confirm() } }
            if actions.canSettle { Button("兑现") { actions.settle() } }
            if actions.canCancel { Button("取消", role: .destructive) { actions.cancel() } }
            if !actions.canEdit && !actions.canConfirm && !actions.canSettle && !actions.canCancel {
                Text("无可用操作")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
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

// MARK: - Confirm dialog model (shared P3 pattern)

struct ConfirmDialog: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let destructive: Bool
    let action: () -> Void
}

#endif
