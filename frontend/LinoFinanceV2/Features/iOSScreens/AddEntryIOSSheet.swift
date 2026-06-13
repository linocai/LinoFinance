import SwiftUI

#if os(iOS)

// AddEntryIOSSheet — D3 记一笔 (iOS · full-screen sheet, liquid glass).
//
// iPhone comp (lf_iphone.png, 右): top bar 取消 / 记一笔 / 保存 → SegmentedPill
// 支出/收入/(信用消费)/转账 → 大金额 + CNY/USD SelectableChip → 标题 → 分类
// SelectableChip 流式 → 支付账户 GlassMenuPicker → 可报销 Toggle.
//
// The double-entry mapping is REUSED UNCHANGED from AddEntryModel.swift
// (AddEntryMapper / AddEntrySegment / currency rules / canSubmit-equivalent gating)
// — identical business logic to the macOS AddEntryPage; only the controls + layout
// are the iOS variant. Save success → refresh + dismiss.

struct AddEntryIOSSheet: View {
    @ObservedObject var model: AppModel
    /// Called after a successful submit so the host can refresh the dashboard.
    var onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Form state (same set as macOS AddEntryPage).
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

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                BloomBackground(animated: false).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SegmentedPill(options: AddEntrySegment.allCases, selection: $segment) { $0.title }
                        amountBlock
                        field("标题") {
                            TextField(segment == .transfer ? "如：信用卡还款" : "如：午餐", text: $title)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.Font.body())
                        }
                        if segment.needsCategory {
                            field("分类") { categoryChips }
                        }
                        if segment == .transfer {
                            field("转出账户") { accountPicker($accountId, placeholder: "转出") }
                            field("转入账户") { accountPicker($transferInAccountId, placeholder: "转入") }
                        } else {
                            field(segment == .creditCharge ? "信用卡账户" : "支付账户") {
                                accountPicker($accountId, placeholder: "账户")
                            }
                        }
                        field("日期") {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                        }
                        if segment.needsCategory {
                            reimbursableSection
                        }
                        previewPanel
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Color.expense)
                                .lineLimit(3)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await submit() } }
                            .fontWeight(.semibold)
                            .disabled(!canSubmit)
                    }
                }
            }
        }
        .task {
            if model.accounts.isEmpty { await model.loadAccounts() }
            if model.categories.isEmpty { await model.loadCategories() }
            if model.rates.isEmpty { await model.loadRates() }
        }
        .onChange(of: segment) { _, _ in
            categoryId = nil
            accountId = nil
            transferInAccountId = nil
        }
        .onChange(of: currency) { _, _ in
            accountId = nil
            transferInAccountId = nil
        }
    }

    // MARK: - Amount block (大金额 + CNY/USD)

    private var amountBlock: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currency.symbol)
                    .font(Theme.Font.cardNumber(.semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField("0", text: $amountText)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .font(Theme.Font.bigNumber())
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                Text(".00")
                    .font(Theme.Font.cardNumber(.semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            HStack(spacing: 8) {
                ForEach(CurrencyCode.allCases, id: \.self) { code in
                    SelectableChip(title: code.rawValue, isSelected: currency == code) {
                        currency = code
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Category chips (flow)

    private var categoryChips: some View {
        let cats = selectableCategories
        return Group {
            if cats.isEmpty {
                Text("暂无可用分类")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                IOSFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(cats) { category in
                        SelectableChip(title: category.name, isSelected: categoryId == category.id) {
                            categoryId = (categoryId == category.id) ? nil : category.id
                        }
                    }
                }
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
            if reimbursable {
                TextField("报销方（如：公司）", text: $reimbursementPayer)
                    .textFieldStyle(.roundedBorder)
                DatePicker("预计报销日", selection: $reimbursementExpectedDate, displayedComponents: .date)
                    .font(Theme.Font.caption())
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    // MARK: - Preview (将写入)

    @ViewBuilder
    private var previewPanel: some View {
        let lines = previewLines
        GlassCard(tint: Theme.Color.link) {
            VStack(alignment: .leading, spacing: 8) {
                Text("将写入")
                    .font(Theme.Font.subtitle(.semibold))
                    .foregroundStyle(Theme.Color.link)
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
                                .lineLimit(1)
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

    // MARK: - Selectable data (mirrors macOS AddEntryPage)

    private var selectableCategories: [CategoryDTO] {
        guard let direction = segment.categoryDirection else { return [] }
        return model.categories
            .filter { $0.isActive && $0.type.rawValue == direction.rawValue }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

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

    // MARK: - Submit gating (identical to macOS canSubmit)

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
            return categoryId != nil && accountId != nil
        }
    }

    // MARK: - Build + submit (reuses AddEntryMapper)

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

    private func accountPicker(_ binding: Binding<String?>, placeholder: String) -> some View {
        let accounts = selectableAccounts
        let selectedName = binding.wrappedValue.flatMap { id in accounts.first(where: { $0.id == id })?.name }
        return GlassMenuPicker(
            label: selectedName ?? (accounts.isEmpty ? "无可用账户" : placeholder),
            isPlaceholder: selectedName == nil,
            disabled: accounts.isEmpty
        ) {
            ForEach(accounts) { account in
                Button(account.name) { binding.wrappedValue = account.id }
            }
        }
    }
}

// MARK: - Flow layout (iOS-local; macOS AddEntryPage has its own private FlowLayout)

private struct IOSFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width - bounds.minX > maxWidth {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#endif
