import SwiftUI

/// 跨平台 sheet：用于在 iOS（也在 macOS 备用）让用户输入投资账户的"当前
/// 余额"，由后端算 delta。
/// 在 iOS 主用，通过 environment.isShowingDailyPnLSheet 唤出。
struct DailyPnLSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var selectedAccountID: String?
    @State private var newBalanceText: String = ""
    @State private var note: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false

    private var investmentAccounts: [AccountDTO] {
        environment.accountsViewModel.accounts.investmentAccounts
    }

    private var selectedAccount: AccountDTO? {
        let candidate = selectedAccountID ?? environment.dailyPnLTargetAccountID ?? investmentAccounts.first?.id
        guard let id = candidate else { return nil }
        return investmentAccounts.first(where: { $0.id == id })
    }

    private var placeholderText: String {
        guard let account = selectedAccount else { return "当前余额" }
        return FinanceFormatter.money(account.currentBalance, currency: account.currency)
    }

    private var parsedNewBalance: Decimal? {
        let trimmed = newBalanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Decimal(string: trimmed)
    }

    private var deltaPreview: String? {
        guard let account = selectedAccount, let newValue = parsedNewBalance else { return nil }
        let delta = newValue - account.currentBalance.value
        let sign = delta > 0 ? "+" : ""
        let formatted = FinanceFormatter.money(DecimalValue(delta), currency: account.currency)
        return "预计变动：\(sign)\(formatted)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账户") {
                    if investmentAccounts.isEmpty {
                        Text("当前没有投资账户")
                            .foregroundStyle(FinanceTokens.Text.secondary)
                    } else if investmentAccounts.count == 1, let only = investmentAccounts.first {
                        Text("\(only.name) · \(only.currency.rawValue)")
                    } else {
                        Picker("投资账户", selection: Binding(
                            get: { selectedAccountID ?? environment.dailyPnLTargetAccountID ?? investmentAccounts.first?.id ?? "" },
                            set: { selectedAccountID = $0 }
                        )) {
                            ForEach(investmentAccounts) { account in
                                Text("\(account.name) · \(account.currency.rawValue)").tag(account.id)
                            }
                        }
                    }
                }

                Section("当前余额") {
                    TextField(placeholderText, text: $newBalanceText)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    if let deltaPreview {
                        Text(deltaPreview)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(FinanceTokens.Text.secondary)
                    }
                }

                Section("备注（可选）") {
                    TextField("例如：盘后调整", text: $note)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(FinanceTokens.State.warning)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("记录今日投资余额")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "提交中…" : "记录") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
#endif
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard selectedAccount != nil else { return false }
        return parsedNewBalance != nil
    }

    @MainActor
    private func submit() async {
        guard let account = selectedAccount, let amount = parsedNewBalance else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await environment.recordDailyPnL(
                accountID: account.id,
                newBalance: amount,
                note: note
            )
            do {
                try await environment.dashboardViewModel.refresh()
                try await environment.accountsViewModel.refresh()
            } catch {
                environment.lastErrorMessage = error.localizedDescription
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismiss() {
        environment.isShowingDailyPnLSheet = false
        environment.dailyPnLTargetAccountID = nil
        newBalanceText = ""
        note = ""
        errorMessage = nil
        selectedAccountID = nil
    }
}
