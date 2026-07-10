import SwiftUI

// AIProposalViews — v3.0.0 P4 ① 提案确认流的跨平台共享视图.
//
// Used verbatim by both the macOS AI 屏 (`AIScreen`) and the iOS 记一笔「AI 解析」
// sheet (`AIProposalSheetIOS`) — D5 独立 AI 屏体验. This is the id-mapping safety
// net the plan calls out: every action in a proposal is listed with an
// expandable detail card; `CreateEntry` / `RecordCreditRepayment` /
// `CreateCashFlowItem` show picker-editable account/category fields (backed by
// the user's REAL, current account/category lists — never a free-text id), so
// an AI-guessed or missing account/category is always visible and correctable
// before anything posts to the ledger. High-risk actions (`VoidEntry`) are
// flagged and gated behind a distinct strong-confirm step, never silently run.

// MARK: - Binding into an EditableAIAction's nested draft

/// The `AIProposalActionKind` case never changes once an `EditableAIAction` is
/// parsed (a CreateEntry action stays `.entry` throughout editing), so these
/// accessors are safe as a one-way "if this case, give me a live Binding into
/// its associated value" bridge — the standard pattern for binding into an
/// enum's associated value.
extension Binding where Value == EditableAIAction {
    var entryDraft: Binding<EditableEntryDraft>? {
        guard case .entry(let initial, let wrapped) = wrappedValue.kind else { return nil }
        return Binding<EditableEntryDraft>(
            get: {
                if case .entry(let draft, _) = wrappedValue.kind { return draft }
                return initial
            },
            set: { newValue in wrappedValue.kind = .entry(newValue, wrapped: wrapped) }
        )
    }

    var cashFlowDraft: Binding<EditableCashFlowDraft>? {
        guard case .cashFlowItem(let initial) = wrappedValue.kind else { return nil }
        return Binding<EditableCashFlowDraft>(
            get: {
                if case .cashFlowItem(let draft) = wrappedValue.kind { return draft }
                return initial
            },
            set: { newValue in wrappedValue.kind = .cashFlowItem(newValue) }
        )
    }
}

// MARK: - One action's expandable detail card

struct AIActionCard: View {
    @Binding var action: EditableAIAction
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded {
                Divider().overlay(Theme.Color.divider)
                if let explanation = action.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                content
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.Radius.button, tint: highRiskTint)
    }

    private var highRiskTint: Color? {
        action.isHighRisk ? Theme.Color.expense : nil
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(action.typeTitle)
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                if action.isHighRisk {
                    StatusBadge(text: "高危", tone: .negative)
                } else {
                    StatusBadge(text: action.riskLevel.financeStatusTitle, tone: action.riskLevel == "medium" ? .warning : .neutral)
                }
                Spacer(minLength: 8)
                if let error = action.validationError(accounts: accounts, categories: categories) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.expense)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch action.kind {
        case .entry:
            if let draft = $action.entryDraft { entryEditor(draft) }
        case .cashFlowItem:
            if let draft = $action.cashFlowDraft { cashFlowEditor(draft) }
        case .voidEntry(let entryId, _):
            voidEntryBody(entryId)
        case .passthrough(let payload):
            passthroughBody(payload)
        }
    }

    // MARK: CreateEntry / RecordCreditRepayment editor

    private func entryEditor(_ draft: Binding<EditableEntryDraft>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            field("标题") {
                TextField("标题", text: draft.title)
                    .textFieldStyle(.roundedBorder)
            }
            field("日期") {
                DatePicker("", selection: draft.date, displayedComponents: .date)
                    .labelsHidden()
            }
            if !draft.wrappedValue.categoryLines.isEmpty {
                field("分类行") {
                    VStack(spacing: 8) {
                        ForEach(draft.categoryLines) { $line in
                            categoryLineRow($line)
                        }
                    }
                }
            }
            if !draft.wrappedValue.accountMovements.isEmpty {
                field("账户流水") {
                    VStack(spacing: 8) {
                        ForEach(draft.accountMovements) { $movement in
                            accountMovementRow($movement)
                        }
                    }
                }
            }
        }
    }

    private func categoryLineRow(_ line: Binding<EditableCategoryLine>) -> some View {
        let matches = matchingCategories(direction: line.wrappedValue.direction)
        return HStack(spacing: 8) {
            StatusBadge(
                text: line.wrappedValue.direction.title,
                tone: line.wrappedValue.direction == .income ? .positive : .neutral
            )
            TextField("0.00", text: line.amountText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 88)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(line.wrappedValue.currency.rawValue)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
            GlassMenuPicker(
                label: categoryName(line.wrappedValue.categoryId) ?? "选择分类",
                isPlaceholder: categoryName(line.wrappedValue.categoryId) == nil,
                disabled: matches.isEmpty
            ) {
                ForEach(matches) { category in
                    Button(category.name) { line.wrappedValue.categoryId = category.id }
                }
            }
        }
    }

    private func accountMovementRow(_ movement: Binding<EditableAccountMovement>) -> some View {
        let matches = candidateAccounts(for: movement.wrappedValue.movementType, currency: movement.wrappedValue.currency)
        return HStack(spacing: 8) {
            Text(movement.wrappedValue.movementType.title)
                .font(Theme.Font.badge(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 64, alignment: .leading)
            TextField("0.00", text: movement.amountText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 88)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(movement.wrappedValue.currency.rawValue)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textSecondary)
            GlassMenuPicker(
                label: accountName(movement.wrappedValue.accountId) ?? "选择账户",
                isPlaceholder: accountName(movement.wrappedValue.accountId) == nil,
                disabled: matches.isEmpty
            ) {
                ForEach(matches) { account in
                    Button(account.name) { movement.wrappedValue.accountId = account.id }
                }
            }
        }
    }

    // MARK: CreateCashFlowItem editor

    private func cashFlowEditor(_ draft: Binding<EditableCashFlowDraft>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            field("标题") {
                TextField("标题", text: draft.title)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                field("金额") {
                    HStack(spacing: 6) {
                        TextField("0.00", text: draft.amountText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(draft.wrappedValue.currency.rawValue)
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
                field("预计日期") {
                    DatePicker("", selection: draft.expectedDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            field("账户（可选）") {
                GlassMenuPicker(
                    label: accountName(draft.wrappedValue.accountId) ?? "不关联",
                    isPlaceholder: accountName(draft.wrappedValue.accountId) == nil
                ) {
                    Button("不关联") { draft.wrappedValue.accountId = nil }
                    ForEach(accounts.filter { $0.currency == draft.wrappedValue.currency }) { account in
                        Button(account.name) { draft.wrappedValue.accountId = account.id }
                    }
                }
            }
            field("分类（可选）") {
                GlassMenuPicker(
                    label: categoryName(draft.wrappedValue.categoryId) ?? "不关联",
                    isPlaceholder: categoryName(draft.wrappedValue.categoryId) == nil
                ) {
                    Button("不关联") { draft.wrappedValue.categoryId = nil }
                    ForEach(categories.filter { $0.type.rawValue == (draft.wrappedValue.direction == "inflow" ? "income" : "expense") }) { category in
                        Button(category.name) { draft.wrappedValue.categoryId = category.id }
                    }
                }
            }
        }
    }

    // MARK: VoidEntry / passthrough

    private func voidEntryBody(_ entryId: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Color.expense)
            Text(entryId.map { "将撤销记录 #\($0.prefix(8))，此操作不可通过 AI 回滚" } ?? "缺少要撤销的记录 id，无法执行")
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(10)
        .background(Theme.Color.expense.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func passthroughBody(_ payload: [String: JSONValueDTO]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("此类型暂不支持在此编辑，将原样提交：")
                .font(Theme.Font.badge())
                .foregroundStyle(Theme.Color.textTertiary)
            ForEach(payload.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top, spacing: 6) {
                    Text(key)
                        .font(Theme.Font.badge(.medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text(payload[key]?.displayText ?? "")
                        .font(Theme.Font.badge())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Lookups

    private func categoryName(_ id: String?) -> String? {
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })?.name
    }

    private func accountName(_ id: String?) -> String? {
        guard let id else { return nil }
        return accounts.first(where: { $0.id == id })?.name
    }

    private func matchingCategories(direction: CategoryDirection) -> [CategoryDTO] {
        categories.filter { $0.isActive && $0.type.rawValue == direction.rawValue }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

    /// Mirrors `AddEntryModel`'s existing segment→account-type mapping:
    /// credit movements only against credit accounts, plain balance_in/out only
    /// against balance accounts, transfer legs against balance OR investment.
    private func candidateAccounts(for movementType: MovementType, currency: CurrencyCode) -> [AccountDTO] {
        let byCurrency = accounts.filter { $0.currency == currency && $0.status == "active" }
        switch movementType {
        case .creditCharge, .creditRepayment:
            return byCurrency.filter { $0.type == .credit }
        case .transferIn, .transferOut:
            return byCurrency.filter { $0.type == .balance || $0.type == .investment }
        case .balanceIn, .balanceOut:
            return byCurrency.filter { $0.type == .balance }
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

// MARK: - Whole-plan review panel (input → actions → confirm/reject/high-risk gate)

struct AIPlanReviewPanel: View {
    @ObservedObject var ai: AIAssistantModel
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]
    /// Called after a successful execute (low/medium risk OR high-risk
    /// confirmed) so the host can refresh AppModel-wide state
    /// (dashboard/accounts/…) — see `AIAssistantModel`'s doc comment.
    var onLedgerChanged: () async -> Void

    var body: some View {
        GlassCard(tint: Theme.Color.link) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let plan = ai.draftPlan {
                    if !plan.sourceText.isEmpty {
                        Text("“\(plan.sourceText)”")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textTertiary)
                            .lineLimit(3)
                    }
                    if let explanation = plan.explanation, !explanation.isEmpty {
                        Text(explanation)
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
                ForEach($ai.editableActions) { $action in
                    AIActionCard(action: $action, accounts: accounts, categories: categories)
                }
                if let pending = ai.pendingHighRiskPlan {
                    highRiskGate(pending)
                } else {
                    if let error = ai.actionError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.expense)
                            .lineLimit(3)
                    }
                    footer
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.Color.brandEnd)
            Text("请核对后再执行")
                .font(Theme.Font.subtitle(.semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TintedActionChip(title: "拒绝", tone: .destructive) {
                Task { await ai.rejectDraft() }
            }
            TintedActionChip(title: "取消", tone: .neutral) {
                ai.discardDraft()
            }
            Spacer()
            PrimaryDarkButton("确认执行", isLoading: ai.isSubmittingDraft) {
                Task {
                    let outcome = await ai.prepareExecution(accounts: accounts, categories: categories)
                    if outcome == .executed {
                        await onLedgerChanged()
                    }
                }
            }
            .disabled(ai.isSubmittingDraft || hasBlockingError)
            .opacity((ai.isSubmittingDraft || hasBlockingError) ? 0.5 : 1)
        }
    }

    private var hasBlockingError: Bool {
        ai.editableActions.contains { $0.validationError(accounts: accounts, categories: categories) != nil }
    }

    private func highRiskGate(_ plan: AIPlanDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("包含高危动作，执行后可能无法撤销（如撤销记录）。请确认。", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Font.body(.medium))
                .foregroundStyle(Theme.Color.expense)
            if let error = ai.actionError {
                Text(error)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
            }
            HStack(spacing: 10) {
                TintedActionChip(title: "取消", tone: .neutral) {
                    Task { await ai.cancelHighRiskExecution() }
                }
                Spacer()
                TintedActionChip(title: "确认执行高危操作", systemImage: "exclamationmark.triangle.fill", tone: .destructive) {
                    Task {
                        let ok = await ai.confirmHighRiskExecution()
                        if ok { await onLedgerChanged() }
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.Color.expense.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - History row (macOS only consumer today, kept cross-platform for reuse)

struct AIPlanHistoryRow: View {
    let plan: AIPlanDTO
    let onOpen: () -> Void
    let onRollback: (String) -> Void

    private var isReviewable: Bool {
        ["requires_confirmation", "auto_confirm_candidate", "approved", "failed", "pending"].contains(plan.status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(plan.sourceText.isEmpty ? "（直接提交的动作）" : plan.sourceText)
                    .font(Theme.Font.caption(.medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 6)
                StatusBadge(text: plan.status.financeStatusTitle, tone: statusTone)
            }
            HStack(spacing: 8) {
                StatusBadge(text: plan.riskLevel.financeStatusTitle, tone: riskTone)
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(10)
        .glassPanel(cornerRadius: Theme.Radius.button)
    }

    @ViewBuilder
    private var actions: some View {
        if isReviewable {
            TintedActionChip(title: "查看 / 编辑", systemImage: "pencil", tone: .action, action: onOpen)
        } else if plan.status == "executed", let action = plan.actions.first(where: { $0.status == "executed" }) {
            TintedActionChip(title: "回滚", tone: .neutral) { onRollback(action.id) }
        }
    }

    private var statusTone: StatusBadge.Tone {
        switch plan.status {
        case "executed": .positive
        case "approved": .pending
        case "rejected", "failed": .negative
        case "rolled_back": .neutral
        default: .warning
        }
    }

    private var riskTone: StatusBadge.Tone {
        switch plan.riskLevel {
        case "high": .negative
        case "medium": .warning
        default: .neutral
        }
    }
}
