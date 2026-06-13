import SwiftUI

#if os(macOS)

// CashFlowFormSheet — D4 新建 / 编辑现金流 (glass modal, P3).
//
// Mirrors v1 `NewCashFlowSheet` / `EditCashFlowSheet` field set:
//   title / direction / cashFlowType / amount(+currency) / expectedDate /
//   account? / category? / note.
// Edit uses `CashFlowItemUpdateRequest` with `Nullable` so account/category can
// be linked, unlinked or left alone. (The v1 monthly-salary recurrence helper is
// out of scope for P3 — a one-shot item per submit; recurrence_rule kept nil.)

/// Direction segments for the SegmentedPill (the underlying state stays a String
/// so all existing direction logic — submit/seed/category filter — is unchanged).
private enum FlowDirection: String, CaseIterable, Identifiable {
    case inflow, outflow, transfer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inflow: "进账"
        case .outflow: "出账"
        case .transfer: "转账"
        }
    }
}

struct CashFlowFormSheet: View {
    @ObservedObject var model: CashFlowModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: Equatable {
        case create
        case edit(CashFlowItemDTO)
    }

    let mode: Mode
    var onSaved: () -> Void

    @State private var title = ""
    @State private var direction = "outflow"
    @State private var cashFlowType = "one_time"
    @State private var amountText = ""
    @State private var currency: CurrencyCode = .cny
    @State private var expectedDate = Date()
    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var note = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isEdit: Bool { if case .edit = mode { return true } ; return false }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Color.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("标题") {
                        TextField("如：房租", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("方向") {
                        SegmentedPill(
                            options: FlowDirection.allCases,
                            selection: Binding(
                                get: { FlowDirection(rawValue: direction) ?? .outflow },
                                set: { direction = $0.rawValue }
                            )
                        ) { $0.title }
                    }
                    field("类型") {
                        GlassMenuPicker(label: CashFlowType.title(cashFlowType)) {
                            ForEach(CashFlowType.allCases, id: \.self) { raw in
                                Button(CashFlowType.title(raw)) { cashFlowType = raw }
                            }
                        }
                    }
                    field("金额") {
                        HStack(spacing: 10) {
                            TextField("0.00", text: $amountText)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.Font.body().monospacedDigit())
                            HStack(spacing: 6) {
                                ForEach(CurrencyCode.allCases, id: \.self) { code in
                                    SelectableChip(title: code.rawValue, isSelected: currency == code) {
                                        currency = code
                                    }
                                }
                            }
                        }
                    }
                    field("预计日期") {
                        DatePicker("", selection: $expectedDate, displayedComponents: .date)
                            .datePickerStyle(.field)
                            .labelsHidden()
                    }
                    field("账户（可选）") {
                        GlassMenuPicker(
                            label: accountId.flatMap { id in selectableAccounts.first { $0.id == id }?.name } ?? "不关联",
                            isPlaceholder: accountId == nil
                        ) {
                            Button("不关联") { accountId = nil }
                            ForEach(selectableAccounts) { account in
                                Button(account.name) { accountId = account.id }
                            }
                        }
                    }
                    if direction != "transfer" {
                        field("分类（可选）") {
                            GlassMenuPicker(
                                label: categoryId.flatMap { id in selectableCategories.first { $0.id == id }?.name } ?? "不关联",
                                isPlaceholder: categoryId == nil
                            ) {
                                Button("不关联") { categoryId = nil }
                                ForEach(selectableCategories) { category in
                                    Button(category.name) { categoryId = category.id }
                                }
                            }
                        }
                    }
                    field("备注") {
                        TextField("可选", text: $note)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(22)
            }
            Divider().overlay(Theme.Color.divider)
            footer
        }
        .frame(width: 520, height: 620)
        .background { BloomBackground(animated: false).opacity(0.9) }
        .onAppear(perform: seed)
        .onChange(of: currency) { _, _ in
            // Account currency must match; drop a now-mismatched account.
            if let id = accountId, let account = model.accounts.first(where: { $0.id == id }),
               account.currency != currency {
                accountId = nil
            }
        }
        .onChange(of: direction) { _, _ in
            // Category direction follows in/out; drop a now-mismatched category.
            categoryId = nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.Color.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(isEdit ? "编辑现金流" : "新建现金流")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("未来预计收支 · 确认 / 兑现 / 取消")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
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
                .keyboardShortcut(.cancelAction)
            PrimaryDarkButton(isEdit ? "保存" : "创建", isLoading: isSubmitting) {
                Task { await submit() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting || !canSubmit)
            .opacity((isSubmitting || !canSubmit) ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var selectableAccounts: [AccountDTO] {
        model.accounts
            .filter { $0.type == .balance && $0.status == "active" && $0.currency == currency }
            .sorted(by: AccountDTO.displayOrdered)
    }

    private var selectableCategories: [CategoryDTO] {
        let wanted: CategoryType = direction == "inflow" ? .income : .expense
        return model.categories
            .filter { $0.isActive && $0.type == wanted }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

    private var canSubmit: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let value = Decimal(string: amountText.trimmingCharacters(in: .whitespaces)), value > 0 else { return false }
        return true
    }

    private func seed() {
        guard case .edit(let item) = mode else { return }
        title = item.title
        direction = item.direction
        cashFlowType = item.cashFlowType
        amountText = NSDecimalNumber(decimal: item.amount.value).stringValue
        currency = item.currency
        expectedDate = item.expectedDate
        accountId = item.accountId
        categoryId = item.categoryId
        note = item.note ?? ""
    }

    @MainActor
    private func submit() async {
        guard let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmedNote.isEmpty ? nil : trimmedNote
        let effectiveCategory = direction == "transfer" ? nil : categoryId
        do {
            switch mode {
            case .create:
                let request = CashFlowItemCreateRequest(
                    title: trimmedTitle,
                    direction: direction,
                    cashFlowType: cashFlowType,
                    amount: DecimalValue(amount),
                    currency: currency,
                    expectedDate: expectedDate,
                    accountId: accountId,
                    categoryId: effectiveCategory,
                    note: noteValue
                )
                try await model.create(request)
            case .edit(let item):
                let request = CashFlowItemUpdateRequest(
                    title: trimmedTitle,
                    direction: direction,
                    cashFlowType: cashFlowType,
                    amount: DecimalValue(amount),
                    currency: currency,
                    expectedDate: expectedDate,
                    accountId: accountId.map(Nullable.value) ?? .null,
                    categoryId: effectiveCategory.map(Nullable.value) ?? .null,
                    note: noteValue
                )
                try await model.update(item.id, request: request)
            }
            errorMessage = nil
            onSaved()
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension CashFlowFormSheet.Mode: Identifiable {
    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let item): return "edit-\(item.id)"
        }
    }
}

#endif
