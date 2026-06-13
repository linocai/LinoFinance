import SwiftUI

#if os(macOS)

// AccountFormSheet — D2 新建 / 编辑账户 (glass modal, P3).
//
// Two modes share one form:
//   • .create → POST /accounts (all fields editable)
//   • .edit   → PATCH /accounts/{id} (SAFE SUBSET only)
//
// IRON RULE (HANDOFF §4.2 + plan §D2): in edit mode `type / currency /
// current_balance / current_liability` are GREYED OUT and never sent — the
// backend schema is `extra="forbid"` so any of those four would 422, and
// balances change ONLY through reconciliation. The submit path uses
// `AccountUpdateRequest`, whose fields cannot carry those four at all.

struct AccountFormSheet: View {
    @ObservedObject var model: AccountsModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: Equatable {
        case create
        case edit(AccountDTO)
    }

    let mode: Mode
    var onSaved: () -> Void

    // Shared fields
    @State private var name = ""
    @State private var accountType: AccountType = .balance
    @State private var currency: CurrencyCode = .cny
    @State private var openingAmountText = ""   // create-only (balance or liability)
    @State private var includeInNetWorth = true
    @State private var statusActive = true
    @State private var creditLimitText = ""
    @State private var statementDayText = ""
    @State private var dueDayText = ""
    @State private var minimumPaymentText = ""
    @State private var notes = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isEdit: Bool { if case .edit = mode { return true } ; return false }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    immutableNotice
                    coreFields
                    if accountType == .credit { creditFields }
                    metaFields
                }
                .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            footer
        }
        .frame(width: 520, height: 640)
        .background { BloomBackground(animated: false).opacity(0.9) }
        .onAppear(perform: seed)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(isEdit ? "编辑账户" : "新建账户")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(isEdit ? "类型 / 币种 / 余额不可改 · 余额经对账变动" : "余额 / 信用 / 投资三类")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var immutableNotice: some View {
        if isEdit {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("类型、币种与余额已锁定，余额请通过「对账」调整。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .glassPanel(cornerRadius: Theme.Radius.button)
        }
    }

    // MARK: - Core fields

    private var coreFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("名称") {
                TextField("如：招商储蓄", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Type — immutable in edit (locked / greyed in GlassMenuPicker).
            field("类型") {
                GlassMenuPicker(label: accountType.title, disabled: isEdit) {
                    ForEach([AccountType.balance, .investment, .credit], id: \.self) { type in
                        Button(type.title) { accountType = type }
                    }
                }
                .opacity(isEdit ? 0.5 : 1)
            }

            // Currency — immutable in edit (locked / greyed in GlassMenuPicker).
            field("币种") {
                GlassMenuPicker(label: "\(currency.symbol) \(currency.rawValue)", disabled: isEdit) {
                    ForEach(CurrencyCode.allCases, id: \.self) { code in
                        Button("\(code.symbol) \(code.rawValue)") { currency = code }
                    }
                }
                .opacity(isEdit ? 0.5 : 1)
            }

            // Opening balance / liability — create only; immutable in edit
            if isEdit {
                field(accountType == .credit ? "当前负债（锁定）" : "当前余额（锁定）") {
                    Text(lockedBalanceText)
                        .font(Theme.Font.body().monospacedDigit())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Theme.Color.textSecondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            } else {
                field(accountType == .credit ? "当前负债" : "当前余额") {
                    TextField("0.00", text: $openingAmountText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Font.body().monospacedDigit())
                }
            }
        }
    }

    private var lockedBalanceText: String {
        guard case .edit(let account) = mode else { return "" }
        let amount = account.type == .credit ? account.currentLiability : account.currentBalance
        let sign = account.type == .credit ? "-" : ""
        return "\(sign)\(account.currency.symbol)\(formatPlain(amount.value))"
    }

    // MARK: - Credit-only fields (editable in both modes)

    private var creditFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("信用额度") {
                TextField("0.00", text: $creditLimitText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Font.body().monospacedDigit())
            }
            HStack(spacing: 12) {
                field("账单日（1-31）") {
                    TextField("如 5", text: $statementDayText)
                        .textFieldStyle(.roundedBorder)
                }
                field("还款日（1-31）") {
                    TextField("如 25", text: $dueDayText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            field("最低还款") {
                TextField("0.00", text: $minimumPaymentText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Font.body().monospacedDigit())
            }
        }
    }

    // MARK: - Meta fields (editable in both modes)

    private var metaFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $includeInNetWorth) {
                Text("计入净资产")
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            .toggleStyle(.switch)

            Toggle(isOn: $statusActive) {
                Text(statusActive ? "状态：启用" : "状态：归档")
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            .toggleStyle(.switch)

            field("备注") {
                TextField("可选", text: $notes)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                PrimaryDarkButton(isEdit ? "保存" : "创建", fullWidth: true, isLoading: isSubmitting) {
                    Task { await submit() }
                }
                .disabled(isSubmitting || !canSubmit)
                .opacity((isSubmitting || !canSubmit) ? 0.5 : 1)
                .keyboardShortcut(.defaultAction)

                SubtleTextButton("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Seed

    private func seed() {
        guard case .edit(let account) = mode else { return }
        name = account.name
        accountType = account.type
        currency = account.currency
        includeInNetWorth = account.includeInNetWorth
        statusActive = account.status == "active"
        creditLimitText = account.creditLimit.map { formatPlain($0.value) } ?? ""
        statementDayText = account.statementDay.map(String.init) ?? ""
        dueDayText = account.dueDay.map(String.init) ?? ""
        minimumPaymentText = account.minimumPayment.map { formatPlain($0.value) } ?? ""
        notes = account.notes ?? ""
    }

    // MARK: - Submit

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .create:
                let opening = Decimal(string: openingAmountText.trimmingCharacters(in: .whitespaces)) ?? 0
                let request = AccountCreateRequest(
                    name: trimmedName,
                    type: accountType,
                    currency: currency,
                    currentBalance: accountType == .credit ? DecimalValue(0) : DecimalValue(opening),
                    currentLiability: accountType == .credit ? DecimalValue(opening) : DecimalValue(0),
                    includeInNetWorth: includeInNetWorth,
                    status: statusActive ? "active" : "archived",
                    creditLimit: accountType == .credit ? decimalOrNil(creditLimitText) : nil,
                    statementDay: accountType == .credit ? Int(statementDayText) : nil,
                    dueDay: accountType == .credit ? Int(dueDayText) : nil,
                    minimumPayment: accountType == .credit ? decimalOrNil(minimumPaymentText) : nil,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
                try await model.createAccount(request)

            case .edit(let account):
                // SAFE SUBSET only — never type/currency/balance/liability.
                let request = AccountUpdateRequest(
                    name: trimmedName,
                    includeInNetWorth: includeInNetWorth,
                    status: statusActive ? "active" : "archived",
                    creditLimit: account.type == .credit ? decimalOrNil(creditLimitText) : nil,
                    statementDay: account.type == .credit ? Int(statementDayText) : nil,
                    dueDay: account.type == .credit ? Int(dueDayText) : nil,
                    minimumPayment: account.type == .credit ? decimalOrNil(minimumPaymentText) : nil,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
                try await model.updateAccount(account.id, request: request)
            }
            errorMessage = nil
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decimalOrNil(_ text: String) -> DecimalValue? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed) else { return nil }
        return DecimalValue(value)
    }

    private func formatPlain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    // MARK: - Builders

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
