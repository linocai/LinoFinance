import SwiftUI

#if os(macOS)

// CycleCreateSheets — D7 create modals (订阅 / 分期 / 信用账单周期).
//
// Each is a glass sheet bound to its real *CreateRequest. They reuse AppModel's
// cached accounts/categories and (for installments) load confirmed entries to
// satisfy the required linkedEntryId.

// MARK: - 新建订阅

struct NewSubscriptionSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var cyclesModel: CyclesModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amountText = ""
    @State private var currency: CurrencyCode = .cny
    @State private var billingInterval = "monthly"
    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var startDate = Date()
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let intervals = ["weekly", "monthly", "yearly"]

    var body: some View {
        CycleSheetScaffold(
            title: "新建订阅",
            icon: "arrow.triangle.2.circlepath",
            subtitle: "周期性扣费规则",
            isSubmitting: isSubmitting,
            canSubmit: canSubmit,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onSubmit: { await submit() }
        ) {
            labeledField("标题") {
                TextField("如：Netflix 会员", text: $title).textFieldStyle(.roundedBorder)
            }
            amountRow($amountText, $currency)
            labeledField("周期") {
                GlassMenuPicker(label: billingInterval.financeStatusTitle) {
                    ForEach(intervals, id: \.self) { iv in
                        Button(iv.financeStatusTitle) { billingInterval = iv }
                    }
                }
            }
            labeledField("扣费账户（可选）") {
                accountPicker($accountId, accounts: balanceAccounts)
            }
            labeledField("分类（可选）") {
                GlassMenuPicker(
                    label: expenseCategories.first { $0.id == categoryId }?.name ?? "未选择",
                    isPlaceholder: categoryId == nil
                ) {
                    Button("未选择") { categoryId = nil }
                    ForEach(expenseCategories) { cat in
                        Button(cat.name) { categoryId = cat.id }
                    }
                }
            }
            labeledField("起始日期") {
                glassDateField($startDate)
            }
            labeledField("备注（可选）") {
                TextField("补充说明", text: $note).textFieldStyle(.roundedBorder)
            }
        }
        .task { await ensureRefData() }
    }

    private var balanceAccounts: [AccountDTO] { model.accounts.filter { $0.currency == currency }.activeBalanceAccounts }
    private var expenseCategories: [CategoryDTO] { model.categories.filter { $0.isActive && $0.type == .expense } }

    private var parsedAmount: DecimalValue? { parseDecimalAmount(amountText).map(DecimalValue.init) }
    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (parsedAmount?.value ?? 0) > 0
    }

    private func ensureRefData() async {
        if model.accounts.isEmpty { await model.loadAccounts() }
        if model.categories.isEmpty { await model.loadCategories() }
    }

    private func submit() async {
        guard let amount = parsedAmount else { return }
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let request = SubscriptionRuleCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            currency: currency,
            accountId: accountId,
            categoryId: categoryId,
            billingInterval: billingInterval,
            startDate: startDate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            _ = try await cyclesModel.createSubscription(request)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 新建分期

struct NewInstallmentSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var cyclesModel: CyclesModel
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [EntryDTO] = []
    @State private var linkedEntryId: String?
    @State private var creditAccountId: String?
    @State private var totalText = ""
    @State private var currency: CurrencyCode = .cny
    @State private var numberOfPayments = 12
    @State private var startDate = Date()
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        CycleSheetScaffold(
            title: "新建分期",
            icon: "creditcard",
            subtitle: "把信用卡大额消费拆成多期",
            isSubmitting: isSubmitting,
            canSubmit: canSubmit,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onSubmit: { await submit() }
        ) {
            labeledField("关联记录") {
                GlassMenuPicker(
                    label: entries.first { $0.id == linkedEntryId }?.title ?? (entries.isEmpty ? "无已确认记录" : "未选择"),
                    isPlaceholder: linkedEntryId == nil,
                    disabled: entries.isEmpty
                ) {
                    ForEach(entries) { entry in
                        Button(entry.title) { linkedEntryId = entry.id }
                    }
                }
            }
            labeledField("信用卡账户") {
                accountPicker($creditAccountId, accounts: creditAccounts)
            }
            amountRow($totalText, $currency, label: "总金额")
            labeledField("期数") {
                Stepper(value: $numberOfPayments, in: 2...60) {
                    Text("\(numberOfPayments) 期")
                        .font(Theme.Font.body().monospacedDigit())
                        .foregroundStyle(Theme.Color.textPrimary)
                }
            }
            if let amount = parsedTotal, numberOfPayments > 0 {
                let per = DecimalValue(amount.value / Decimal(numberOfPayments))
                labeledField("每期约") {
                    AmountText(value: per, currency: currency, font: Theme.Font.subtitle(.semibold), color: Theme.Color.textSecondary)
                }
            }
            labeledField("起始日期") {
                glassDateField($startDate)
            }
            labeledField("备注（可选）") {
                TextField("补充说明", text: $note).textFieldStyle(.roundedBorder)
            }
        }
        .task {
            if model.accounts.isEmpty { await model.loadAccounts() }
            if let result = try? await model.apiClient.listEntries() {
                entries = result.filter { $0.status == .confirmed }
            }
        }
    }

    private var creditAccounts: [AccountDTO] { model.accounts.filter { $0.currency == currency }.activeCreditAccounts }
    private var parsedTotal: DecimalValue? { parseDecimalAmount(totalText).map(DecimalValue.init) }
    private var canSubmit: Bool {
        linkedEntryId != nil && creditAccountId != nil && (parsedTotal?.value ?? 0) > 0 && numberOfPayments >= 2
    }

    private func submit() async {
        guard let entryId = linkedEntryId, let account = creditAccountId, let total = parsedTotal else { return }
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let request = InstallmentPlanCreateRequest(
            linkedEntryId: entryId,
            creditAccountId: account,
            totalAmount: total,
            currency: currency,
            numberOfPayments: numberOfPayments,
            startDate: startDate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            _ = try await cyclesModel.createInstallment(request)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 新建账单周期

struct NewStatementCycleSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var cyclesModel: CyclesModel
    @Environment(\.dismiss) private var dismiss

    @State private var creditAccountId: String?
    @State private var cycleStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var cycleEnd = Date()
    @State private var statementDate = Date()
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 20, to: Date()) ?? Date()
    @State private var statementAmountText = ""
    @State private var minimumText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        CycleSheetScaffold(
            title: "新建账单周期",
            icon: "calendar",
            subtitle: "登记信用卡账单周期",
            isSubmitting: isSubmitting,
            canSubmit: canSubmit,
            errorMessage: errorMessage,
            onCancel: { dismiss() },
            onSubmit: { await submit() }
        ) {
            labeledField("信用卡账户") {
                accountPicker($creditAccountId, accounts: model.accounts.activeCreditAccounts)
            }
            HStack(spacing: 12) {
                labeledField("周期开始") { glassDateField($cycleStart) }
                labeledField("周期结束") { glassDateField($cycleEnd) }
            }
            HStack(spacing: 12) {
                labeledField("出账日") { glassDateField($statementDate) }
                labeledField("还款日") { glassDateField($dueDate) }
            }
            labeledField("出账金额") {
                TextField("0.00", text: $statementAmountText).textFieldStyle(.roundedBorder).font(Theme.Font.body().monospacedDigit())
            }
            labeledField("最低还款") {
                TextField("0.00", text: $minimumText).textFieldStyle(.roundedBorder).font(Theme.Font.body().monospacedDigit())
            }
        }
        .task { if model.accounts.isEmpty { await model.loadAccounts() } }
    }

    private var selectedAccount: AccountDTO? { model.accounts.first { $0.id == creditAccountId } }
    private var canSubmit: Bool { creditAccountId != nil }

    private func submit() async {
        guard let account = selectedAccount else { return }
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let request = CreditStatementCycleCreateRequest(
            creditAccountId: account.id,
            cycleStartDate: cycleStart,
            cycleEndDate: cycleEnd,
            statementDate: statementDate,
            dueDate: dueDate,
            currency: account.currency,
            statementAmount: parseDecimalAmount(statementAmountText).map(DecimalValue.init) ?? DecimalValue(0),
            minimumPayment: parseDecimalAmount(minimumText).map(DecimalValue.init) ?? DecimalValue(0)
        )
        do {
            _ = try await cyclesModel.createStatementCycle(request)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Shared scaffold + small builders

struct CycleSheetScaffold<Content: View>: View {
    let title: String
    let icon: String
    let subtitle: String
    let isSubmitting: Bool
    let canSubmit: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSubmit: () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
                    Text(subtitle).font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            HStack(spacing: 12) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.expense)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                SubtleTextButton("取消", action: onCancel).keyboardShortcut(.cancelAction)
                PrimaryDarkButton("创建", isLoading: isSubmitting) {
                    Task { await onSubmit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || !canSubmit)
                .opacity((isSubmitting || !canSubmit) ? 0.5 : 1)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 600)
        .background { BloomBackground(animated: false).opacity(0.9) }
    }
}

// Shared little field/picker builders (module-private free functions used by the sheets).

@ViewBuilder
func labeledField<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(label)
            .font(Theme.Font.caption(.medium))
            .foregroundStyle(Theme.Color.textSecondary)
        content()
    }
}

@ViewBuilder
func amountRow(_ amount: Binding<String>, _ currency: Binding<CurrencyCode>, label: String = "金额") -> some View {
    labeledField(label) {
        HStack(spacing: 10) {
            TextField("0.00", text: amount)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Font.cardNumber().monospacedDigit())
            GlassMenuPicker(label: "\(currency.wrappedValue.symbol) \(currency.wrappedValue.rawValue)") {
                ForEach(CurrencyCode.allCases, id: \.self) { code in
                    Button("\(code.symbol) \(code.rawValue)") { currency.wrappedValue = code }
                }
            }
            .frame(width: 120)
        }
    }
}

/// A native compact DatePicker wrapped in a glass field — matches AddEntryPage's
/// 日期 field convention (R3): `.field` style inside a glassPanel chrome.
@ViewBuilder
func glassDateField(_ selection: Binding<Date>) -> some View {
    DatePicker("", selection: selection, displayedComponents: .date)
        .datePickerStyle(.field)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: Theme.Radius.button)
}

@ViewBuilder
func accountPicker(_ binding: Binding<String?>, accounts: [AccountDTO]) -> some View {
    let selectedName = accounts.first { $0.id == binding.wrappedValue }?.name
    GlassMenuPicker(
        label: selectedName ?? (accounts.isEmpty ? "无可用账户" : "未选择"),
        isPlaceholder: selectedName == nil,
        disabled: accounts.isEmpty
    ) {
        Button("未选择") { binding.wrappedValue = nil }
        ForEach(accounts) { account in
            Button(account.name) { binding.wrappedValue = account.id }
        }
    }
}

#endif
