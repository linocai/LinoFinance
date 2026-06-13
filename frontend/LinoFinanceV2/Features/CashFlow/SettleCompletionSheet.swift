import SwiftUI

#if os(macOS)

// SettleCompletionSheet — D4 兑现补齐 (glass modal, P3).
//
// Shown when a cash-flow item lacks `account_id` / `category_id` and the user
// taps 兑现. Mirrors v1 `SettleCompletionSheet`: pick the missing account +
// category, PATCH them, then settle in one go (`CashFlowModel.completeAndSettle`).

struct SettleCompletionSheet: View {
    @ObservedObject var model: CashFlowModel
    let item: CashFlowItemDTO
    @Environment(\.dismiss) private var dismiss

    var onSettled: () -> Void

    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(model: CashFlowModel, item: CashFlowItemDTO, onSettled: @escaping () -> Void) {
        self.model = model
        self.item = item
        self.onSettled = onSettled
        _accountId = State(initialValue: item.accountId)
        _categoryId = State(initialValue: item.categoryId)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    Text("兑现前请补齐缺失的账户和分类。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                    field("账户") {
                        Picker("", selection: $accountId) {
                            Text("请选择").tag(Optional<String>.none)
                            ForEach(selectableAccounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        .labelsHidden()
                    }
                    field("分类") {
                        Picker("", selection: $categoryId) {
                            Text("请选择").tag(Optional<String>.none)
                            ForEach(selectableCategories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            footer
        }
        .frame(width: 460, height: 480)
        .background { BloomBackground(animated: false).opacity(0.9) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("兑现现金流")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("将生成一条正式记账记录")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var summaryCard: some View {
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
                AmountText(
                    value: item.amount,
                    currency: item.currency,
                    font: Theme.Font.subtitle(.semibold),
                    color: item.direction == "inflow" ? Theme.Color.income : Theme.Color.expense
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            SubtleTextButton("取消") { dismiss() }
            PrimaryDarkButton("兑现", isLoading: isSubmitting) {
                Task { await submit() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting || accountId == nil || categoryId == nil)
            .opacity((isSubmitting || accountId == nil || categoryId == nil) ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
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

    @MainActor
    private func submit() async {
        guard let accountId, let categoryId else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await model.completeAndSettle(item, accountId: accountId, categoryId: categoryId)
            errorMessage = nil
            onSettled()
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassPanel(
                    cornerRadius: Theme.Radius.button,
                    shadow: Theme.ShadowSpec(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
                )
        }
    }
}

#endif
