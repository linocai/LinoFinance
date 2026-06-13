import SwiftUI

#if os(macOS)

// ReconciliationScreen — D9 对账 (macOS · self-contained · presentable as a sheet).
//
// Presented FROM AccountsScreen (P3) because reconciliation is the ONLY path a
// balance account's balance can change (plan §D9). Self-contained: owns its own
// title + close button + @StateObject ReconciliationModel, so it drops cleanly
// into a `.sheet { }` without the host supplying chrome.
//
// Flow (plan §D9): select 账户 → 系统余额 (read-only) → 实际余额 (input) → 差额
// (auto-computed) → 说明 → 「生成对账调整」. Balances only change here.
//
// Data:
//   • listReconciliationAccounts() → ReconciliationAccountsResponseDTO
//       (.items[ReconciliationAccountDTO] each carrying expected/current/delta)
//   • createAccountAdjustment(AccountAdjustmentCreateRequest(accountId:
//       actualAmount:reason:note:))
struct ReconciliationScreen: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var reconModel: ReconciliationModel

    // Adjustment form state
    @State private var selectedAccountId: String?
    @State private var actualText = ""
    @State private var reason = ""
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    init(model: AppModel) {
        self.model = model
        _reconModel = StateObject(wrappedValue: ReconciliationModel(apiClient: model.apiClient))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch reconModel.state {
                    case .idle, .loading:
                        loadingState
                    case .failed(let message):
                        failedState(message)
                    case .loaded:
                        overviewSection
                        adjustmentForm
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 620, height: 720)
        .background {
            BloomBackground(animated: false).opacity(0.9)
        }
        .task {
            if reconModel.snapshot == nil { await reconModel.load() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("对账")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("系统记录余额 vs 实际余额 · 账户余额只经此处变动")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Overview (system vs actual)

    private var overviewSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("账户对账总览")
                        .font(Theme.Font.subtitle(.semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Text("阈值 \(FinanceFormatter.money(reconModel.snapshot?.threshold ?? DecimalValue(0)))")
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                if reconModel.rows.isEmpty {
                    Text("没有可对账的账户。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                } else {
                    ForEach(reconModel.rows) { row in
                        reconRow(row)
                        if row.id != reconModel.rows.last?.id {
                            Divider().overlay(Theme.Color.divider)
                        }
                    }
                }
            }
        }
    }

    private func reconRow(_ row: ReconciliationAccountDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.accountName)
                        .font(Theme.Font.body(.medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                    StatusBadge(text: row.accountType.title, tone: .neutral)
                    if row.needsAdjustment {
                        StatusBadge(text: "需调整", tone: .warning)
                    }
                }
                Text("系统余额 \(FinanceFormatter.money(row.expectedAmount, currency: row.currency)) · 实际 \(FinanceFormatter.money(row.currentAmount, currency: row.currency))")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("差额")
                    .font(Theme.Font.badge())
                    .foregroundStyle(Theme.Color.textTertiary)
                AmountText(
                    value: row.deltaAmount,
                    currency: row.currency,
                    showsPositiveSign: true,
                    font: Theme.Font.subtitle(.semibold),
                    color: deltaColor(row.deltaAmount)
                )
                Button("对此账户调整") {
                    selectAccount(row)
                }
                .buttonStyle(.borderless)
                .font(Theme.Font.caption())
                .tint(Theme.Color.link)
            }
        }
        .padding(.vertical, 4)
    }

    private func deltaColor(_ value: DecimalValue) -> Color {
        if value.value == 0 { return Theme.Color.textTertiary }
        return value.value < 0 ? Theme.Color.expense : Theme.Color.income
    }

    // MARK: - Adjustment form

    private var adjustmentForm: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("生成对账调整")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)

                field("账户") {
                    Picker("", selection: $selectedAccountId) {
                        Text(reconModel.rows.isEmpty ? "无可对账账户" : "未选择").tag(Optional<String>.none)
                        ForEach(reconModel.rows) { row in
                            Text(row.accountName).tag(Optional(row.accountId))
                        }
                    }
                    .labelsHidden()
                    .disabled(reconModel.rows.isEmpty)
                    .onChange(of: selectedAccountId) { _, _ in
                        syncActualToSystem()
                    }
                }

                if let row = selectedRow {
                    field("系统余额（只读）") {
                        AmountText(
                            value: row.expectedAmount,
                            currency: row.currency,
                            font: Theme.Font.cardNumber(),
                            color: Theme.Color.textPrimary
                        )
                    }
                    field("实际余额") {
                        HStack(spacing: 10) {
                            TextField("0.00", text: $actualText)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.Font.cardNumber().monospacedDigit())
                            Text(row.currency.rawValue)
                                .font(Theme.Font.body(.medium))
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    field("差额（自动算）") {
                        if let actual = parsedActual {
                            let delta = DecimalValue(actual.value - row.expectedAmount.value)
                            AmountText(
                                value: delta,
                                currency: row.currency,
                                showsPositiveSign: true,
                                font: Theme.Font.subtitle(.semibold),
                                color: deltaColor(delta)
                            )
                        } else {
                            Text("输入实际余额后自动计算")
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                    field("说明") {
                        TextField("如：核对支付宝余额", text: $reason)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("备注（可选）") {
                        TextField("补充说明", text: $note)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    Text("先选择一个账户开始对账。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.expense)
                }
                if let successMessage {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.income)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Text("生成对账调整").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting || !canSubmit)
            }
        }
    }

    // MARK: - Selection / gating

    private var selectedRow: ReconciliationAccountDTO? {
        guard let selectedAccountId else { return nil }
        return reconModel.rows.first { $0.accountId == selectedAccountId }
    }

    private var parsedActual: DecimalValue? {
        guard let decimal = parseDecimalAmount(actualText) else { return nil }
        return DecimalValue(decimal)
    }

    private var canSubmit: Bool {
        guard selectedRow != nil, parsedActual != nil else { return false }
        return !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func selectAccount(_ row: ReconciliationAccountDTO) {
        selectedAccountId = row.accountId
        errorMessage = nil
        successMessage = nil
        syncActualToSystem()
    }

    /// Pre-fill 实际余额 with the system balance so the user only edits the delta.
    private func syncActualToSystem() {
        guard let row = selectedRow else { return }
        actualText = FinanceFormatter.money(row.currentAmount, currency: row.currency)
            .replacingOccurrences(of: row.currency.symbol, with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    @MainActor
    private func submit() async {
        guard let row = selectedRow, let actual = parsedActual else { return }
        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await reconModel.submitAdjustment(
                accountId: row.accountId,
                actualAmount: actual,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
            )
            successMessage = "已生成对账调整，账户余额已更新。"
            reason = ""
            note = ""
            // Refresh the host app's account cache so AccountsScreen reflects it.
            await model.loadAccounts()
            await model.loadDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - States & helpers

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在加载对账数据…")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("对账加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.expense)
                Text(message)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                Button("重试") { Task { await reconModel.load() } }
                    .buttonStyle(.bordered)
            }
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
