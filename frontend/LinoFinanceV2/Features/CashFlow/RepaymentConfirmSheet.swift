import SwiftUI

#if os(macOS)

// RepaymentConfirmSheet — 信用还款直接结算 (glass modal, v2.1.0 P1).
//
// Shown when 确认还款 is tapped on a transfer cash-flow item (a credit-card
// repayment receivable). The user picks the repayment SOURCE balance account +
// date; submitting builds the transfer-only settle entry
// (transfer_out on the source + credit_repayment on the credit account) via
// `CashFlowModel.settleRepayment` and settles in one shot. R0 controls only
// (GlassMenuPicker / DatePicker(.field) / PrimaryDarkButton / SubtleTextButton).

struct RepaymentConfirmSheet: View {
    @ObservedObject var model: CashFlowModel
    let item: CashFlowItemDTO
    @Environment(\.dismiss) private var dismiss

    var onSettled: () -> Void

    @State private var sourceAccountId: String?
    @State private var repaymentDate = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(model: CashFlowModel, item: CashFlowItemDTO, onSettled: @escaping () -> Void) {
        self.model = model
        self.item = item
        self.onSettled = onSettled
        // Pre-pick the only eligible source if there's exactly one.
        let sources = model.repaymentSourceAccounts(for: item)
        _sourceAccountId = State(initialValue: sources.count == 1 ? sources.first?.id : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    Text("选择还款来源余额账户和还款日期，确认后将从该账户扣款并冲减信用账户负债。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                    field("还款来源账户") {
                        GlassMenuPicker(
                            label: selectedSourceName ?? "请选择",
                            isPlaceholder: sourceAccountId == nil
                        ) {
                            ForEach(selectableSources) { account in
                                Button(account.name) { sourceAccountId = account.id }
                            }
                        }
                    }
                    field("还款日期") {
                        DatePicker("", selection: $repaymentDate, displayedComponents: .date)
                            .datePickerStyle(.field)
                            .labelsHidden()
                    }
                    if let previewText = previewText {
                        Text(previewText)
                            .font(Theme.Font.caption(.medium))
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    if selectableSources.isEmpty {
                        Label("没有与该现金流币种匹配的余额账户，请先创建。", systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.expense)
                    }
                }
                .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            footer
        }
        .frame(width: 460, height: 440)
        .background { BloomBackground(animated: false).opacity(0.9) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("确认还款")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("将生成一条信用还款记录")
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
                    Text("信用还款 · \(creditAccountName)")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
                AmountText(
                    value: item.amount,
                    currency: item.currency,
                    font: Theme.Font.subtitle(.semibold),
                    color: Theme.Color.expense
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
            PrimaryDarkButton("确认还款", isLoading: isSubmitting) {
                Task { await submit() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting || sourceAccountId == nil)
            .opacity((isSubmitting || sourceAccountId == nil) ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var selectableSources: [AccountDTO] {
        model.repaymentSourceAccounts(for: item)
    }

    private var selectedSourceName: String? {
        sourceAccountId.flatMap { id in model.accounts.first(where: { $0.id == id })?.name }
    }

    private var creditAccountName: String {
        model.repaidCreditAccount(for: item)?.name
            ?? model.accountName(item.accountId)
            ?? "信用账户"
    }

    private var previewText: String? {
        guard let name = selectedSourceName else { return nil }
        let amount = FinanceFormatter.money(item.amount, currency: item.currency)
        return "将从「\(name)」还款 \(amount)"
    }

    @MainActor
    private func submit() async {
        guard let sourceAccountId else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await model.settleRepayment(item, sourceAccountId: sourceAccountId, date: repaymentDate)
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
        }
    }
}

#endif
