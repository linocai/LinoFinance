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
    /// v3.0.0 P5 — non-nil ⇒ EDIT mode: prefill from this entry, submit via PATCH.
    var editingEntry: EntryDTO? = nil
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
    // Edit prefill runs once; `isApplyingPrefill` suppresses the reset onChanges.
    @State private var didPrefill = false
    @State private var isApplyingPrefill = false

    // v3.0.0 P4 ① — iOS「AI 解析」入口 (D5): 粘贴/输入一句话代替手填表单。
    @State private var showingAIProposal = false

    private var isEditing: Bool { editingEntry != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                BloomBackground(animated: false).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SegmentedPill(options: AddEntrySegment.allCases, selection: $segment) { $0.title }
                        // AI 一句话记账 only makes sense for a NEW entry, not an edit.
                        if !isEditing { aiEntryRow }
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
            .navigationTitle(isEditing ? "编辑记录" : "记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(isEditing ? "保存修改" : "保存") { Task { await submit() } }
                            .fontWeight(.semibold)
                            .disabled(!canSubmit)
                    }
                }
            }
        }
        .task {
            // 每次打开记一笔都重取，确保设置里新加的分类 / 账户 / 汇率即时可见
            // （只在空时取会读到旧缓存）。
            await model.loadAccounts()
            await model.loadCategories()
            await model.loadRates()
            if let editingEntry, !didPrefill {
                applyPrefill(editingEntry)
                didPrefill = true
            } else if editingEntry == nil {
                applyInitialDefaultAccounts()
            }
        }
        .onChange(of: segment) { _, _ in
            guard !isApplyingPrefill else { return }
            categoryId = nil
            clearInvalidatedAccounts()
        }
        .onChange(of: currency) { _, _ in
            guard !isApplyingPrefill else { return }
            clearInvalidatedAccounts()
        }
        .sheet(isPresented: $showingAIProposal) {
            // The AI path writes the ledger itself (unlike the manual form below,
            // which still goes through `submit()`) — on success it dismisses
            // itself, then this closure dismisses the outer 记一笔 sheet too and
            // notifies the host, mirroring `submit()`'s own onSubmitted+dismiss.
            AIProposalSheetIOS(model: model) {
                onSubmitted()
                dismiss()
            }
        }
    }

    // MARK: - AI 解析入口 (v3.0.0 P4 ①, D5)

    private var aiEntryRow: some View {
        Button {
            showingAIProposal = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("改用 AI 解析一句话记账")
                    .font(Theme.Font.caption(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.Color.brandEnd)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassPanel(cornerRadius: Theme.Radius.button, tint: Theme.Color.brandEnd)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Default account selection (v2.5.0 评审修补 · H 重要-2, mirrors macOS AddEntryPage)
    //
    // Two separate paths, deliberately NOT merged into one "nil-or-invalid →
    // fill first" rule — that rule cannot honor a manual pick surviving a
    // currency round-trip (switching away invalidates it to nil then
    // immediately refills with first; switching back invalidates THAT and
    // refills with a possibly different first account, silently swapping the
    // user's chosen account). See reviewer 重要-2 /
    // archive/REVIEW_REPORT_v2.5.0.md.
    //
    // - `.task` (sheet first opened): fill first-if-nil once.
    // - `onChange(segment/currency)`: an account no longer in the refreshed
    //   `selectableAccounts` is cleared to nil — never refilled with first.
    //   nil blocks `canSubmit`, forcing an explicit re-pick (safe outcome).
    //   A still-valid manual pick is never touched by either path.

    /// Initial-open only: fill `accountId` with the first selectable account
    /// if nil. Transfer only defaults the OUT leg.
    private func applyInitialDefaultAccounts() {
        if accountId == nil {
            accountId = selectableAccounts.first?.id
        }
    }

    /// Edit mode: reverse-map the entry into the form (mirrors macOS AddEntryPage).
    /// `isApplyingPrefill` shields the segment/currency reset onChanges while the
    /// prefill assigns state; it lowers on the next runloop tick.
    private func applyPrefill(_ entry: EntryDTO) {
        guard let prefill = AddEntryPrefill(entry: entry) else { return }
        isApplyingPrefill = true
        segment = prefill.segment
        currency = prefill.currency
        title = prefill.title
        amountText = prefill.amountText
        categoryId = prefill.categoryId
        accountId = prefill.accountId
        transferInAccountId = prefill.transferInAccountId
        date = prefill.date
        reimbursable = prefill.reimbursable
        reimbursementPayer = prefill.reimbursementPayer
        if let expected = prefill.reimbursementExpectedDate {
            reimbursementExpectedDate = expected
        }
        DispatchQueue.main.async { isApplyingPrefill = false }
    }

    /// Segment/currency changed: drop any account selection that no longer
    /// belongs to the refreshed `selectableAccounts`. Never refills with first.
    private func clearInvalidatedAccounts() {
        let accounts = selectableAccounts
        if let current = accountId, !accounts.contains(where: { $0.id == current }) {
            accountId = nil
        }
        if segment == .transfer {
            if let current = transferInAccountId, !accounts.contains(where: { $0.id == current }) {
                transferInAccountId = nil
            }
        } else {
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
                    .onChange(of: amountText) { _, newValue in
                        let sanitized = sanitizeAmountInput(newValue)
                        if sanitized != newValue { amountText = sanitized }
                    }
                // v2.5.0 P2 · B: ".00" is a decorative cents hint for whole-number
                // entry ("123" → "123 .00"); once the user types their own "." it
                // must not double up into "123.33.00".
                if !amountText.contains(".") {
                    Text(".00")
                        .font(Theme.Font.cardNumber(.semibold))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
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
        case .transfer:
            base = model.accounts.activeTransferAccounts
        case .expense, .income:
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
            if let editingEntry {
                _ = try await model.updateEntry(editingEntry.id, request: request)
            } else {
                _ = try await model.submitEntry(request)
            }
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
