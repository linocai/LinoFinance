import SwiftUI

#if os(iOS)

// CashFlowIOSView — D4 现金流 (iOS · narrow, liquid glass).
//
// Mirrors macOS CashFlowScreen: a glass card of hairline-divided rows; each row =
// 图标 + 标题 + status/type 标签 + 双币金额 + 内联 TintedActionChip (确认/兑现/取消).
// Chips fire directly (no native confirm dialog), same as macOS R2. On the narrow
// column the amount sits with the title block and the action chips wrap to a row
// underneath. Settle that needs account/category opens an iOS completion sheet.
//
// Reuses CashFlowModel unchanged (cross-platform): sortedItems, accountName,
// confirm / cancel / attemptSettle / completeAndSettle, canShowSettleAction.

struct CashFlowIOSView: View {
    @ObservedObject var model: AppModel
    @StateObject private var cashFlowModel: CashFlowModel

    @State private var settleItem: CashFlowItemDTO?

    init(model: AppModel) {
        self.model = model
        _cashFlowModel = StateObject(wrappedValue: CashFlowModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .sheet(item: $settleItem) { item in
            SettleCompletionSheetIOS(model: cashFlowModel, item: item)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("现金流")
                .font(Theme.Font.pageTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Text("未来预计收支 · 确认 / 兑现 / 取消")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
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
                Button { cashFlowModel.actionError = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .padding(12)
            .glassPanel(cornerRadius: Theme.Radius.button, tint: Theme.Color.expense)
        }
    }

    @ViewBuilder
    private var content: some View {
        if cashFlowModel.items.isEmpty {
            emptyState
        } else {
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(cashFlowModel.sortedItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.Color.divider) }
                        row(item)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Row (narrow: title/badges + amount on top, action chips wrap below)

    private func row(_ item: CashFlowItemDTO) -> some View {
        let actionable = item.status == "expected" || item.status == "confirmed"
        let settled = item.status == "settled"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: directionSymbol(item))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint(item))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(Theme.Font.body(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        StatusBadge(text: item.statusTitle, tone: item.statusTone)
                        StatusBadge(text: CashFlowType.title(item.cashFlowType), tone: .neutral)
                    }
                    Text(subtitle(item))
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                AmountText(value: item.amount, currency: item.currency,
                           font: Theme.Font.subtitle(.semibold), color: tint(item))
            }
            if actionable {
                actionChips(item)
                    .padding(.leading, 37)
            }
        }
        .opacity(settled ? 0.55 : 1)
    }

    @ViewBuilder
    private func actionChips(_ item: CashFlowItemDTO) -> some View {
        HStack(spacing: 8) {
            if item.status == "expected" {
                TintedActionChip(title: "确认", tone: .positive) {
                    Task { await cashFlowModel.confirm(item.id) }
                }
            }
            if item.canShowSettleAction {
                TintedActionChip(title: "兑现", tone: .action) { settle(item) }
            }
            TintedActionChip(title: "取消", tone: .neutral) {
                Task { await cashFlowModel.cancel(item.id) }
            }
            Spacer(minLength: 0)
        }
    }

    private func settle(_ item: CashFlowItemDTO) {
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

    private func subtitle(_ item: CashFlowItemDTO) -> String {
        "\(Self.dateText(item.expectedDate)) · \(cashFlowModel.accountName(item.accountId) ?? "未关联账户")"
    }

    private func directionSymbol(_ item: CashFlowItemDTO) -> String {
        switch item.direction {
        case "inflow": "arrow.down.circle.fill"
        case "outflow": "arrow.up.circle.fill"
        default: "arrow.left.arrow.right.circle.fill"
        }
    }

    private func tint(_ item: CashFlowItemDTO) -> Color {
        if item.status == "settled" { return Theme.Color.textTertiary }
        switch item.direction {
        case "inflow": return Theme.Color.income
        case "outflow": return Theme.Color.expense
        default: return Theme.Color.textSecondary
        }
    }

    // MARK: - States

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("还没有现金流")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("在 macOS 端创建预计收支后，这里会列出未来事件。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f
    }()

    private static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }
}

// MARK: - 兑现补齐 (iOS sheet)
//
// Shown when 兑现 hits an item missing account/category. Pick the missing pair,
// PATCH + settle in one go (CashFlowModel.completeAndSettle). NavigationStack
// chrome with a 取消 / 兑现 toolbar.

private struct SettleCompletionSheetIOS: View {
    @ObservedObject var model: CashFlowModel
    let item: CashFlowItemDTO
    @Environment(\.dismiss) private var dismiss

    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(model: CashFlowModel, item: CashFlowItemDTO) {
        self.model = model
        self.item = item
        _accountId = State(initialValue: item.accountId)
        _categoryId = State(initialValue: item.categoryId)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BloomBackground(animated: false).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(Theme.Font.subtitle(.semibold))
                                        .foregroundStyle(Theme.Color.textPrimary)
                                    Text("\(item.directionTitle) · \(CashFlowType.title(item.cashFlowType))")
                                        .font(Theme.Font.caption())
                                        .foregroundStyle(Theme.Color.textSecondary)
                                }
                                Spacer()
                                AmountText(value: item.amount, currency: item.currency,
                                           font: Theme.Font.subtitle(.semibold),
                                           color: item.direction == "inflow" ? Theme.Color.income : Theme.Color.expense)
                            }
                        }
                        Text("兑现前请补齐缺失的账户和分类。")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textSecondary)
                        field("账户") {
                            GlassMenuPicker(
                                label: selectedAccountName ?? "请选择",
                                isPlaceholder: accountId == nil
                            ) {
                                ForEach(selectableAccounts) { account in
                                    Button(account.name) { accountId = account.id }
                                }
                            }
                        }
                        field("分类") {
                            GlassMenuPicker(
                                label: selectedCategoryName ?? "请选择",
                                isPlaceholder: categoryId == nil
                            ) {
                                ForEach(selectableCategories) { category in
                                    Button(category.name) { categoryId = category.id }
                                }
                            }
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Color.expense)
                                .lineLimit(2)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("兑现现金流")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("兑现") { Task { await submit() } }
                        .disabled(isSubmitting || accountId == nil || categoryId == nil)
                }
            }
        }
    }

    private var selectableAccounts: [AccountDTO] {
        model.accounts
            .filter { $0.type == .balance && $0.status == "active" && $0.currency == item.currency }
            .sorted(by: AccountDTO.displayOrdered)
    }

    private var selectableCategories: [CategoryDTO] {
        let wanted: CategoryType = item.direction == "inflow" ? .income : .expense
        return model.categories
            .filter { $0.isActive && $0.type == wanted }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

    private var selectedAccountName: String? {
        accountId.flatMap { id in model.accounts.first(where: { $0.id == id })?.name }
    }

    private var selectedCategoryName: String? {
        categoryId.flatMap { id in model.categories.first(where: { $0.id == id })?.name }
    }

    @MainActor
    private func submit() async {
        guard let accountId, let categoryId else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await model.completeAndSettle(item, accountId: accountId, categoryId: categoryId)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            content()
        }
    }
}

#endif
