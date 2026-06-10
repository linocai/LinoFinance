#if os(macOS)
import SwiftUI

/// macOS sidebar 今日盈亏快速录入面板。
/// 用户输入投资账户的"当前余额"，由后端算 delta；前端不做加减法。
struct DailyPnLSidebarPanel: View {
    @Bindable var environment: AppEnvironment
    @State private var selectedAccountID: String?
    @State private var newBalanceText: String = ""
    @State private var note: String = ""
    @State private var feedbackMessage: String?
    @State private var feedbackTint: Color = FinanceTokens.State.income
    @State private var isSubmitting: Bool = false
    @State private var dismissFeedbackTask: Task<Void, Never>?

    private var investmentAccounts: [AccountDTO] {
        environment.accountsViewModel.accounts.investmentAccounts
    }

    private var selectedAccount: AccountDTO? {
        guard let id = selectedAccountID ?? investmentAccounts.first?.id else { return nil }
        return investmentAccounts.first(where: { $0.id == id })
    }

    private var placeholderText: String {
        guard let account = selectedAccount else { return "当前余额" }
        return FinanceFormatter.money(account.currentBalance, currency: account.currency)
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard selectedAccount != nil else { return false }
        return parseDecimalAmount(newBalanceText) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if investmentAccounts.count > 1 {
                Picker("账户", selection: Binding(
                    get: { selectedAccountID ?? investmentAccounts.first?.id ?? "" },
                    set: { selectedAccountID = $0 }
                )) {
                    ForEach(investmentAccounts) { account in
                        Text("\(account.name) · \(account.currency.rawValue)").tag(account.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else if let only = investmentAccounts.first {
                Text("\(only.name) · \(only.currency.rawValue)")
                    .font(.caption)
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }

            TextField(placeholderText, text: $newBalanceText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13).monospacedDigit())

            TextField("备注（可选）", text: $note)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack(spacing: 6) {
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    Text(isSubmitting ? "记录中…" : "记录")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSubmit)
            }

            if let feedback = feedbackMessage {
                Text(feedback)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(feedbackTint)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .glassBackground(radius: FinanceTokens.Radius.md, strength: .regular, elevation: nil)
    }

    @MainActor
    private func submit() async {
        guard let account = selectedAccount else { return }
        guard let amount = parseDecimalAmount(newBalanceText) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await environment.recordDailyPnL(
                accountID: account.id,
                newBalance: amount,
                note: note
            )
            let prefix = result.deltaAmount.value > 0 ? "+" : ""
            feedbackMessage = "已记录 \(prefix)\(FinanceFormatter.money(result.deltaAmount, currency: result.currency))"
            feedbackTint = result.deltaAmount.value >= 0 ? FinanceTokens.State.income : FinanceTokens.State.expense
            newBalanceText = ""
            note = ""
            do {
                try await environment.dashboardViewModel.refresh()
                try await environment.accountsViewModel.refresh()
            } catch {
                environment.lastErrorMessage = error.localizedDescription
            }
            dismissFeedbackTask?.cancel()
            dismissFeedbackTask = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run { feedbackMessage = nil }
                }
            }
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackTint = FinanceTokens.State.warning
        }
    }
}
#endif
