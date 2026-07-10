import SwiftUI

#if os(macOS)

// AddEntryPage — D3 记一笔 as a RIGHT-SIDE FULL PAGE (R1, Phase A ·去模态).
//
// Comp source: lf_addentry.png / lf_seg.png / lf_save.png — the sidebar stays
// visible and the content area becomes 记一笔 (NOT a `.sheet`). Layout top→bottom:
//   SegmentedPill 支出/收入/(信用消费)/转账 → big amount (`bigNumber`) + CNY/USD
//   toggle → 标题 → 分类 as `SelectableChip` flow → 账户 / 日期 → 可报销 → soft
//   brand-tinted "将写入" preview box → PrimaryDarkButton("保存", fullWidth) +
//   SubtleTextButton("取消").
//
// This page renders INSIDE MacGlassScene's existing ScrollView + content padding
// (leading 226 / trailing 28 / vertical 28), so it does NOT add its own outer
// ScrollView or leading inset — same convention as OverviewView / CashFlowScreen.
//
// The double-entry mapping (AddEntryMapper), preview lines, currency rules and
// submit gating are reused UNCHANGED from AddEntryModel.swift — R1 only swaps the
// controls + layout. `onClose()` returns to the previous screen (called on a
// successful save and on 取消); ⌘N still drives presentation from the App.

struct AddEntryPage: View {
    @ObservedObject var model: AppModel

    /// v3.0.0 P5 — non-nil ⇒ EDIT mode: the form is prefilled from this entry and
    /// 保存 sends PATCH (void+recreate) instead of POST. The caller passes only
    /// entries whose shape the simple form can represent (see `AddEntryPrefill`).
    var editingEntry: EntryDTO? = nil

    /// Called to leave the page (back to the previous sidebar destination).
    var onClose: () -> Void
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

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    // Edit prefill runs once; `isApplyingPrefill` suppresses the
    // segment/currency reset onChange handlers while the prefill assigns state.
    @State private var didPrefill = false
    @State private var isApplyingPrefill = false

    private var isEditing: Bool { editingEntry != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            formCard
            previewPanel
            footer
        }
        .frame(maxWidth: 720, alignment: .leading)
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
            // Skip while the edit prefill programmatically sets the segment
            // (otherwise it would wipe the prefilled category/account).
            guard !isApplyingPrefill else { return }
            categoryId = nil
            clearInvalidatedAccounts()
        }
        .onChange(of: currency) { _, _ in
            // Account currency must match the movement currency.
            guard !isApplyingPrefill else { return }
            clearInvalidatedAccounts()
        }
    }

    /// Edit mode: reverse-map the entry into the form. Sets `isApplyingPrefill`
    /// so the segment/currency reset handlers don't clobber the assigned
    /// category/account; the flag is lowered on the next runloop tick, after
    /// SwiftUI has processed these mutations (and fired the guarded onChanges).
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

    // MARK: - Default account selection (v2.5.0 评审修补 · H 重要-2)
    //
    // Two separate paths, deliberately NOT merged into one "nil-or-invalid →
    // fill first" rule (that rule cannot honor "manual pick survives a
    // round-trip": switching currency away invalidates a manual pick to nil,
    // which the OLD merged rule then immediately refilled with first — so
    // switching back would invalidate THAT and refill with a possibly
    // different first account, silently swapping the user's chosen account
    // for another one. See reviewer 重要-2 / archive/REVIEW_REPORT_v2.5.0.md).
    //
    // - `.task` (page first opened): fill first-if-nil once. Convenience only
    //   applies on initial open.
    // - `onChange(segment/currency)`: if the current value is no longer in
    //   the refreshed `selectableAccounts`, clear it to nil — never refill
    //   with first. A cleared/nil selection blocks `canSubmit` and forces an
    //   explicit re-pick, which is the safe outcome (see H 项 D3=甲 口径).
    //   A still-valid manual pick is never touched by either path.

    /// Initial-open only: fill `accountId` with the first selectable account
    /// if nil. Transfer only defaults the OUT leg (`accountId`); the IN leg
    /// stays nil so the user must make an explicit choice (defaulting both to
    /// the same account would make `out == into`, permanently failing
    /// `canSubmit`).
    private func applyInitialDefaultAccounts() {
        if accountId == nil {
            accountId = selectableAccounts.first?.id
        }
    }

    /// Segment/currency changed: drop any account selection that no longer
    /// belongs to the refreshed `selectableAccounts`. Never refills with
    /// first — an invalidated pick becomes "unselected", not "someone else's
    /// account".
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isEditing ? "编辑记录" : "记一笔")
                .font(Theme.Font.pageTitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Text(isEditing ? "保存后原记录作废、生成新记录" : "复式记账 · 保存即确认")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // MARK: - Form card

    private var formCard: some View {
        GlassCard(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                // Segment
                SegmentedPill(options: AddEntrySegment.allCases, selection: $segment) { $0.title }

                // Big amount + currency toggle
                amountBlock

                // Title
                field("标题") {
                    TextField(segment == .transfer ? "如：信用卡还款" : "如：午餐", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Font.body())
                }

                // Category chips (non-transfer only)
                if segment.needsCategory {
                    field("分类") { categoryChips }
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

            // CNY / USD toggle (small SelectableChip pair)
            HStack(spacing: 8) {
                ForEach(CurrencyCode.allCases, id: \.self) { code in
                    SelectableChip(title: code.rawValue, isSelected: currency == code) {
                        currency = code
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Category chips

    private var categoryChips: some View {
        let cats = selectableCategories
        return Group {
            if cats.isEmpty {
                Text("暂无可用分类")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                FlowChips(cats) { category in
                    SelectableChip(title: category.name, isSelected: categoryId == category.id) {
                        categoryId = (categoryId == category.id) ? nil : category.id
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

    // MARK: - Preview (将写入) — soft brand-tinted box

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
        .frame(maxWidth: 720, alignment: .leading)
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

    // MARK: - Footer (保存 / 取消)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                PrimaryDarkButton(isEditing ? "保存修改" : "保存", fullWidth: true, isLoading: isSubmitting) {
                    Task { await submit() }
                }
                .disabled(isSubmitting || !canSubmit)
                .opacity((isSubmitting || !canSubmit) ? 0.5 : 1)

                SubtleTextButton("取消") { onClose() }
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    // MARK: - Selectable data

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
            if let editingEntry {
                _ = try await model.updateEntry(editingEntry.id, request: request)
            } else {
                _ = try await model.submitEntry(request)
            }
            errorMessage = nil
            onSubmitted()
            onClose()
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

// MARK: - FlowChips — simple wrapping chip layout for category selection

private struct FlowChips<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(data) { element in
                content(element)
            }
        }
    }
}

/// Minimal flow (wrapping) layout — places subviews left-to-right, wrapping to a
/// new line when the row width is exceeded.
private struct FlowLayout: Layout {
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
