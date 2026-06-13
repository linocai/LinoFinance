import SwiftUI

#if os(macOS)

// AddEntrySheet — D3 记一笔 (macOS glass modal · double-entry · decision-gate D
// "简单态默认 + 高级态可展开").
//
// SIMPLE MODE (default, end-to-end submittable):
//   支出 / 收入 / 信用消费 / 转账 segment → 金额 + 币种 → 标题 → 分类 → 账户(s)
//   → 日期 → 可报销 toggle. Mapping via AddEntryMapper (see AddEntryModel.swift).
//   The bottom "将写入" panel previews the resulting category lines + account
//   movements so the user SEES the double entry before submitting (HANDOFF §4.3).
//   Submit is DISABLED until all required fields are present (no draft fallback).
//
// ADVANCED MODE (P2 = disclosure skeleton only): a labelled section explaining the
// manual multi-line editor and that simple mode already covers daily use. The full
// manual category-line / account-movement editor lands in P3+ (see P2 report). We
// deliberately do NOT ship a half-wired manual editor.

struct AddEntrySheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful submit so the host can refresh the dashboard.
    var onSubmitted: () -> Void

    // Form state
    @State private var segment: AddEntrySegment = .expense
    @State private var amountText = ""
    @State private var currency: CurrencyCode = .cny
    @State private var title = ""
    @State private var categoryId: String?
    @State private var accountId: String?
    @State private var transferInAccountId: String?
    @State private var date = Date()
    @State private var reimbursable = false
    @State private var reimbursementPayer = ""
    @State private var reimbursementExpectedDate = Date()
    @State private var advancedExpanded = false

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    simpleForm
                    previewPanel
                    advancedSection
                }
                .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            footer
        }
        .frame(width: 560, height: 680)
        .background {
            BloomBackground(animated: false)
                .opacity(0.9)
        }
        .task {
            // Ensure accounts / categories / rates are loaded for the pickers.
            if model.accounts.isEmpty { await model.loadAccounts() }
            if model.categories.isEmpty { await model.loadCategories() }
            if model.rates.isEmpty { await model.loadRates() }
        }
        .onChange(of: segment) { _, _ in
            // Reset selections that no longer apply to the new segment.
            categoryId = nil
            accountId = nil
            transferInAccountId = nil
        }
        .onChange(of: currency) { _, _ in
            // Account currency must match the movement currency, so switching
            // currency invalidates any account already picked (the picker now
            // shows only matching-currency accounts).
            accountId = nil
            transferInAccountId = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("记一笔")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("复式记账 · 提交即确认")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Simple form

    private var simpleForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Segment
            Picker("", selection: $segment) {
                ForEach(AddEntrySegment.allCases) { seg in
                    Text(seg.title).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Amount + currency
            field("金额") {
                HStack(spacing: 10) {
                    TextField("0.00", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Font.cardNumber().monospacedDigit())
                    Picker("", selection: $currency) {
                        ForEach(CurrencyCode.allCases, id: \.self) { code in
                            Text("\(code.symbol) \(code.rawValue)").tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            // Title
            field("标题") {
                TextField(segment == .transfer ? "如：信用卡还款" : "如：午餐", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            // Category (non-transfer only)
            if segment.needsCategory {
                field("分类") {
                    Picker("", selection: $categoryId) {
                        Text("未选择").tag(Optional<String>.none)
                        ForEach(selectableCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .labelsHidden()
                }
            }

            // Accounts
            if segment == .transfer {
                field("转出账户") { accountPicker($accountId, accounts: selectableAccounts, placeholder: "转出") }
                field("转入账户") { accountPicker($transferInAccountId, accounts: selectableAccounts, placeholder: "转入") }
            } else {
                field(segment == .creditCharge ? "信用卡账户" : "支付账户") {
                    accountPicker($accountId, accounts: selectableAccounts, placeholder: "账户")
                }
            }

            // Date
            field("日期") {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
            }

            // Reimbursable (non-transfer only)
            if segment.needsCategory {
                reimbursableSection
            }
        }
    }

    private var reimbursableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $reimbursable) {
                Text("可报销")
                    .font(Theme.Font.body(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            .toggleStyle(.switch)

            if reimbursable {
                HStack(spacing: 10) {
                    TextField("报销方（如：公司）", text: $reimbursementPayer)
                        .textFieldStyle(.roundedBorder)
                    DatePicker("预计报销日", selection: $reimbursementExpectedDate, displayedComponents: .date)
                        .datePickerStyle(.field)
                        .font(Theme.Font.caption())
                }
                .padding(.leading, 2)
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    // MARK: - Preview (将写入)

    @ViewBuilder
    private var previewPanel: some View {
        let lines = previewLines
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("将写入")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                if lines.isEmpty {
                    Text("填写金额与账户后，这里会显示复式结果")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                } else {
                    ForEach(lines) { line in
                        HStack(spacing: 8) {
                            Text(line.kind)
                                .font(Theme.Font.badge(.semibold))
                                .foregroundStyle(Theme.Color.textTertiary)
                                .frame(width: 56, alignment: .leading)
                            Text(line.label)
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Color.textSecondary)
                            Spacer(minLength: 8)
                            AmountText(
                                value: signedValue(line),
                                currency: line.currency,
                                showsPositiveSign: line.signedNegative == false,
                                font: Theme.Font.caption(.semibold),
                                color: amountColor(line)
                            )
                        }
                    }
                }
            }
        }
    }

    private func signedValue(_ line: EntryPreviewLine) -> DecimalValue {
        guard line.signedNegative == true else { return line.amount }
        return DecimalValue(-line.amount.value)
    }

    private func amountColor(_ line: EntryPreviewLine) -> Color {
        switch line.signedNegative {
        case .some(true): Theme.Color.expense
        case .some(false): Theme.Color.income
        case .none: Theme.Color.textSecondary
        }
    }

    // MARK: - Advanced (disclosure skeleton, P3+ for the full editor)

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("高级模式可手动编辑多条分类行与多条账户流水（例如一笔记账拆到多个分类、或一次涉及多个账户）。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("日常记账用上面的简单模式即可。完整的手动多行编辑器将在后续 Phase 提供。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Text("高级")
                .font(Theme.Font.body(.medium))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("提交")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting || !canSubmit)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Selectable data

    /// Categories filtered by the segment's direction (expense/income), active only.
    private var selectableCategories: [CategoryDTO] {
        guard let direction = segment.categoryDirection else { return [] }
        return model.categories
            .filter { $0.isActive && $0.type.rawValue == direction.rawValue }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

    /// Accounts the segment can use: expense/income/transfer → balance accounts;
    /// creditCharge → credit accounts. When USD is selected, only matching-currency
    /// accounts are valid (movement currency must equal account currency).
    private var selectableAccounts: [AccountDTO] {
        let base: [AccountDTO]
        switch segment {
        case .creditCharge:
            base = model.accounts.activeCreditAccounts
        case .expense, .income, .transfer:
            base = model.accounts.activeBalanceAccounts
        }
        return base.filter { $0.currency == currency }
    }

    // MARK: - Submit gating

    private var parsedAmount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: trimmed), value > 0 else { return nil }
        return value
    }

    private var canSubmit: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard parsedAmount != nil else { return false }
        if currency == .usd && model.latestUSDRate == nil { return false }
        switch segment {
        case .transfer:
            guard let out = accountId, let into = transferInAccountId, out != into else { return false }
            return true
        case .expense, .income, .creditCharge:
            // reimbursementExpectedDate defaults to today and is always non-nil
            // once 可报销 is toggled, so the backend's "reimbursable line needs an
            // expected date" rule is satisfied without extra gating here.
            return categoryId != nil && accountId != nil
        }
    }

    // MARK: - Build + submit

    private func currentInput() -> AddEntryMapper.Input {
        AddEntryMapper.Input(
            segment: segment,
            title: title,
            amount: parsedAmount ?? 0,
            currency: currency,
            date: date,
            categoryId: categoryId,
            accountId: accountId,
            transferInAccountId: transferInAccountId,
            reimbursable: reimbursable,
            reimbursementPayer: reimbursementPayer.isEmpty ? nil : reimbursementPayer,
            reimbursementExpectedDate: reimbursable ? reimbursementExpectedDate : nil,
            usdRateId: model.latestUSDRate?.id
        )
    }

    private var previewLines: [EntryPreviewLine] {
        guard let amount = parsedAmount else { return [] }
        let value = DecimalValue(amount)
        switch segment {
        case .transfer:
            guard let out = accountId, let into = transferInAccountId else { return [] }
            return [
                EntryPreviewLine(kind: "账户流水", label: "\(accountName(out)) transfer_out", amount: value, currency: currency, signedNegative: true),
                EntryPreviewLine(kind: "账户流水", label: "\(accountName(into)) transfer_in", amount: value, currency: currency, signedNegative: false),
            ]
        case .expense, .income, .creditCharge:
            guard let movementType = segment.singleMovementType, let categoryId else { return [] }
            let isExpense = segment.categoryDirection == .expense
            var lines: [EntryPreviewLine] = []
            lines.append(EntryPreviewLine(
                kind: "分类行",
                label: categoryName(categoryId),
                amount: value,
                currency: currency,
                signedNegative: isExpense
            ))
            if let accountId {
                lines.append(EntryPreviewLine(
                    kind: "账户流水",
                    label: "\(accountName(accountId)) \(movementType.rawValue)",
                    amount: value,
                    currency: currency,
                    signedNegative: isExpense
                ))
            }
            return lines
        }
    }

    private func accountName(_ id: String) -> String {
        model.accounts.first(where: { $0.id == id })?.name ?? "账户"
    }

    private func categoryName(_ id: String) -> String {
        model.categories.first(where: { $0.id == id })?.name ?? "分类"
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let request = try AddEntryMapper.makeRequest(currentInput())
            _ = try await model.submitEntry(request)
            errorMessage = nil
            onSubmitted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Small builders

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
            content()
        }
    }

    private func accountPicker(_ binding: Binding<String?>, accounts: [AccountDTO], placeholder: String) -> some View {
        Picker("", selection: binding) {
            Text(accounts.isEmpty ? "无可用账户" : "未选择").tag(Optional<String>.none)
            ForEach(accounts) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }
        .labelsHidden()
        .disabled(accounts.isEmpty)
    }
}

#endif
