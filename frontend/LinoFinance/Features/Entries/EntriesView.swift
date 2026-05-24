import SwiftUI

enum EntryStatusFilter: String, CaseIterable, Identifiable {
    case all, draft, confirmed, voided
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .draft: "草稿"
        case .confirmed: "已确认"
        case .voided: "已作废"
        }
    }
}

/// 记账页 —— 用 Dashboard 卡片语言重设计。
/// SectionHeader + SegmentedSwitcher + HeroSummary（本月支出/收入）+ 按日期分组卡片。
struct EntriesView: View {
    @Bindable var environment: AppEnvironment
    @State private var statusFilter: EntryStatusFilter = .all
    @State private var confirmation: ConfirmAction?

    private var filteredEntries: [EntryDTO] {
        let entries: [EntryDTO]
        switch statusFilter {
        case .all: entries = environment.entriesViewModel.entries
        default: entries = environment.entriesViewModel.entries.filter { $0.status.rawValue == statusFilter.rawValue }
        }
        let trimmed = environment.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.note?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    kicker: "Entries",
                    title: "记账",
                    description: "单笔记录、分类拆分和账户流水"
                ) {
                    Button {
                        environment.beginNewEntry()
                    } label: {
                        Label("新建记录", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 12) {
                    SegmentedSwitcher(options: EntryStatusFilter.allCases, selection: $statusFilter) { $0.title }
                        .frame(maxWidth: 320)
                    Spacer()
                    if !environment.entriesViewModel.expenseCategories.contains(where: { $0.name == "日常支出" }) {
                        Button {
                            Task { await createQuickExpenseCategory() }
                        } label: {
                            Label("补一个支出分类", systemImage: "tag")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if environment.entriesViewModel.entries.isEmpty {
                    EmptyState(
                        title: "还没有记录",
                        message: "创建账户和分类后，就可以添加第一条单笔记账。",
                        systemImage: "square.and.pencil",
                        actionTitle: "新建记录",
                        action: environment.beginNewEntry
                    )
                } else {
                    EntriesHeroCard(entries: monthlyEntries, categories: environment.entriesViewModel.categories)

                    if filteredEntries.isEmpty {
                        Text("当前过滤下没有记录。")
                            .font(.system(size: 13))
                            .foregroundStyle(FinanceTokens.Text.secondary)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .glassBackground(strength: .regular, elevation: nil)
                    } else {
                        ForEach(groupedEntries, id: \.key) { group in
                            entriesSectionCard(group: group)
                        }
                    }
                }

                if let message = environment.entriesViewModel.errorMessage {
                    ErrorBanner(
                        message: message,
                        onRetry: {
                            Task { try? await environment.entriesViewModel.refresh() }
                        },
                        onDismiss: {
                            environment.entriesViewModel.errorMessage = nil
                        }
                    )
                }
            }
            .padding(.horizontal, entriesPagePadding)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .moduleFrame()
        .task {
            try? await environment.entriesViewModel.refresh()
        }
        .alert(confirmation?.title ?? "确认操作", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), presenting: confirmation) { item in
            Button(item.confirmTitle, role: item.role) {
                item.action()
                confirmation = nil
            }
            Button("取消", role: .cancel) { confirmation = nil }
        } message: { item in
            Text(item.message)
        }
    }

    private var entriesPagePadding: CGFloat {
#if os(iOS)
        16
#else
        28
#endif
    }

    // MARK: - Aggregations

    private var monthlyEntries: [EntryDTO] {
        let now = Date()
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        return environment.entriesViewModel.entries.filter { $0.date >= monthStart && $0.status == .confirmed }
    }

    private struct DateGroup {
        let key: String
        let date: Date
        let title: String
        let entries: [EntryDTO]
    }

    private var groupedEntries: [DateGroup] {
        let calendar = Calendar.current
        let entries = filteredEntries.sorted { $0.date > $1.date }
        let dictionary = Dictionary(grouping: entries) { entry -> Date in
            calendar.startOfDay(for: entry.date)
        }
        return dictionary.keys.sorted(by: >).map { dayStart in
            DateGroup(
                key: "\(dayStart.timeIntervalSince1970)",
                date: dayStart,
                title: dayLabel(for: dayStart),
                entries: dictionary[dayStart] ?? []
            )
        }
    }

    private func dayLabel(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今日" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 EEEE"
        return f.string(from: day)
    }

    @ViewBuilder
    private func entriesSectionCard(group: DateGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.title)
                    .font(FinanceTypography.headline)
                    .foregroundStyle(FinanceTokens.Text.primary)
                Spacer()
                Text("\(group.entries.count) 条")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().background(FinanceTokens.Stroke.soft)
                    }
                    EntryListRowItem(
                        entry: entry,
                        accounts: environment.accountsViewModel.accounts,
                        categories: environment.entriesViewModel.categories,
                        confirm: confirm
                    )
                    .onTapGesture { environment.inspectorSelection = .entry(entry) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(strength: .strong, elevation: .soft)
    }

    private func createQuickExpenseCategory() async {
        do {
            try await environment.entriesViewModel.createCategory(
                CategoryCreateRequest(name: "日常支出", type: .expense, parentId: nil)
            )
        } catch {
            environment.lastErrorMessage = error.localizedDescription
        }
    }

    private func confirm(_ entry: EntryDTO, operation: String) {
        confirmation = ConfirmAction(
            title: operation == "confirm" ? "确认草稿记录？" : "作废记录？",
            message: operation == "confirm" ? "确认后会正式影响账户余额。" : "作废会回滚已确认记录对余额、账单和报销的影响。",
            confirmTitle: operation == "confirm" ? "确认" : "作废",
            role: operation == "confirm" ? nil : .destructive
        ) {
            Task {
                do {
                    if operation == "confirm" {
                        try await environment.entriesViewModel.confirmEntry(entry.id)
                    } else {
                        try await environment.entriesViewModel.voidEntry(entry.id)
                    }
                    // Defensive double-refresh so monthlyEntries reflects the
                    // post-write state even if a sibling write races.
                    try await environment.entriesViewModel.refresh()
                    try await environment.accountsViewModel.refresh()
                    try await environment.dashboardViewModel.refresh()
                    try await environment.reimbursementsViewModel.refresh()
                    try await environment.creditViewModel.refresh()
                    try await environment.reportsViewModel.refresh()
                } catch {
                    environment.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Hero summary card

private struct EntriesHeroCard: View {
    let entries: [EntryDTO]
    let categories: [CategoryDTO]

    private func categoryById(_ id: String) -> CategoryDTO? {
        categories.first(where: { $0.id == id })
    }

    private var totals: (expense: Decimal, income: Decimal) {
        var expense: Decimal = 0
        var income: Decimal = 0
        for entry in entries {
            for line in entry.categoryLines {
                let cny = line.convertedCnyAmount?.value ?? line.amount.value
                if let cat = categoryById(line.categoryId) {
                    if cat.type == .expense { expense += cny }
                    if cat.type == .income { income += cny }
                }
            }
        }
        return (expense, income)
    }

    private struct CategoryStat: Identifiable {
        let id: String
        let name: String
        let amount: Decimal
    }

    private var topExpenseCategories: [CategoryStat] {
        var bucket: [String: Decimal] = [:]
        for entry in entries {
            for line in entry.categoryLines {
                let cny = line.convertedCnyAmount?.value ?? line.amount.value
                if let cat = categoryById(line.categoryId), cat.type == .expense {
                    bucket[cat.name, default: 0] += cny
                }
            }
        }
        return bucket
            .map { CategoryStat(id: $0.key, name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本月支出")
                        .font(FinanceTypography.sectionKicker)
                        .kickerTracking()
                        .foregroundStyle(FinanceTokens.Text.secondary)
                    PrivacyAmount(
                        value: "-" + FinanceFormatter.money(DecimalValue(totals.expense), currency: .cny),
                        font: FinanceTypography.statValue,
                        tint: FinanceTokens.State.expense
                    )
                    if totals.income > 0 {
                        Text("本月收入 +\(FinanceFormatter.money(DecimalValue(totals.income), currency: .cny))")
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(FinanceTokens.State.income)
                    }
                }
                Spacer(minLength: 12)
                AccountIconTile(systemImage: "square.and.pencil", tint: FinanceTokens.Brand.primary)
            }

            if !topExpenseCategories.isEmpty {
                FlowChips(items: topExpenseCategories.map { stat in
                    "\(stat.name) ¥\(formatCompact(stat.amount))"
                })
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(
            strength: .strong,
            accent: AnyShapeStyle(FinanceTokens.Halo.brandCorner),
            elevation: .elevated
        )
    }

    private func formatCompact(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).intValue
        if number >= 10000 {
            return String(format: "%.1fk", Double(number) / 1000)
        }
        return "\(number)"
    }
}

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(FinanceTokens.Surface.glass)
                            .overlay { Capsule().stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5) }
                    )
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Row item with menu

private struct EntryListRowItem: View {
    let entry: EntryDTO
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]
    let confirm: (EntryDTO, String) -> Void

    private var primaryLine: EntryCategoryLineDTO? { entry.categoryLines.first }
    private var primaryMovement: AccountMovementDTO? { entry.accountMovements.first }
    private var account: AccountDTO? { primaryMovement.flatMap { mv in accounts.first(where: { $0.id == mv.accountId }) } }
    private var category: CategoryDTO? { primaryLine.flatMap { line in categories.first(where: { $0.id == line.categoryId }) } }

    private var iconSymbol: String {
        switch category?.type {
        case .income: return "arrow.down.left.circle"
        case .expense: return "arrow.up.right.circle"
        default: return entry.status == .confirmed ? "checkmark.circle" : "circle.dotted"
        }
    }

    private var iconTint: Color {
        switch category?.type {
        case .income: return FinanceTokens.State.income
        case .expense: return account?.type == .credit ? FinanceTokens.State.credit : FinanceTokens.State.expense
        default: return FinanceTokens.State.pending
        }
    }

    private var amountTint: Color { iconTint }
    private var amountPrefix: String {
        switch category?.type {
        case .income: return "+"
        case .expense: return "-"
        default: return ""
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AccountIconTile(systemImage: iconSymbol, tint: iconTint)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FinanceTokens.Text.primary)
                        .lineLimit(1)
                    StatusTag(title: entry.status.title, style: entry.status == .confirmed ? .confirmed : .draft)
                }
                Text("\((account?.name).map { "\($0) · " } ?? "")\(category?.name ?? "未分类") · \(FinanceFormatter.shortDate(entry.date))")
                    .font(FinanceTypography.caption)
                    .foregroundStyle(FinanceTokens.Text.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let primaryLine {
                PrivacyAmount(
                    value: amountPrefix + FinanceFormatter.money(primaryLine.amount, currency: primaryLine.currency),
                    font: .system(size: 14, weight: .semibold).monospacedDigit(),
                    tint: amountTint,
                    alignment: .trailing
                )
            }

            Menu {
                if entry.status == .draft {
                    Button("确认") { confirm(entry, "confirm") }
                }
                if entry.status != .voided {
                    Button("作废", role: .destructive) { confirm(entry, "void") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FinanceTokens.Text.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if entry.status == .draft {
                Button("确认") { confirm(entry, "confirm") }
            }
            if entry.status != .voided {
                Button("作废", role: .destructive) { confirm(entry, "void") }
            }
        }
    }
}

private enum EntryFormMode: String, CaseIterable, Identifiable {
    case expense
    case income
    case creditCharge
    case creditRepayment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "余额支出"
        case .income: "余额收入"
        case .creditCharge: "信用消费"
        case .creditRepayment: "信用还款"
        }
    }

    var categoryType: CategoryType? {
        switch self {
        case .expense, .creditCharge: .expense
        case .income: .income
        case .creditRepayment: nil
        }
    }

    var categoryDirection: CategoryDirection? {
        switch self {
        case .expense, .creditCharge: .expense
        case .income: .income
        case .creditRepayment: nil
        }
    }

    var movementType: MovementType {
        switch self {
        case .expense: .balanceOut
        case .income: .balanceIn
        case .creditCharge: .creditCharge
        case .creditRepayment: .creditRepayment
        }
    }

    var usesBalanceAccount: Bool {
        self == .expense || self == .income
    }

    var usesCreditAccount: Bool {
        self == .creditCharge || self == .creditRepayment
    }

    var supportsReimbursement: Bool {
        self == .expense || self == .creditCharge
    }
}

struct NewEntrySheet: View {
    @Bindable var environment: AppEnvironment
    @State private var mode: EntryFormMode = .expense
    @State private var title = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var status: EntryStatus = .confirmed
    @State private var selectedBalanceAccountID: String?
    @State private var selectedCreditAccountID: String?
    @State private var selectedCategoryID: String?
    @State private var selectedStatementCycleID: String?
    @State private var newCategoryName = ""
    @State private var note = ""
    @State private var isReimbursable = false
    @State private var reimbursementPayer = "company"
    @State private var reimbursementExpectedDate = Date()
    @State private var errorMessage: String?

    private var balanceAccounts: [AccountDTO] {
        environment.accountsViewModel.accounts.balanceAccounts
    }

    private var creditAccounts: [AccountDTO] {
        environment.accountsViewModel.accounts.creditAccounts
    }

    private var availableCategories: [CategoryDTO] {
        guard let categoryType = mode.categoryType else { return [] }
        return environment.entriesViewModel.categories
            .filter { $0.type == categoryType && $0.isActive }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

    private var openStatementCycles: [CreditStatementCycleDTO] {
        environment.creditViewModel.cycles
            .filter { cycle in
                guard let creditAccountID = selectedCreditAccountID else { return true }
                return cycle.creditAccountId == creditAccountID
            }
            .filter { $0.status != "paid" && $0.status != "closed" }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建单笔记录")
                .font(.title2.weight(.semibold))

            Form {
                Picker("类型", selection: $mode) {
                    ForEach(EntryFormMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField("标题", text: $title)
                TextField("金额", text: $amount)
                DatePicker("日期", selection: $date, displayedComponents: .date)
                Picker("状态", selection: $status) {
                    Text("已确认").tag(EntryStatus.confirmed)
                    Text("草稿").tag(EntryStatus.draft)
                }

                if mode.usesBalanceAccount {
                    Picker(mode == .income ? "收款账户" : "付款账户", selection: balanceAccountSelection) {
                        Text("选择余额账户").tag(Optional<String>.none)
                        ForEach(balanceAccounts) { account in
                            Text("\(account.name) · \(account.currency.rawValue)").tag(Optional(account.id))
                        }
                    }
                }

                if mode.usesCreditAccount {
                    Picker("信用账户", selection: creditAccountSelection) {
                        Text("选择信用卡").tag(Optional<String>.none)
                        ForEach(creditAccounts) { account in
                            Text("\(account.name) · \(account.currency.rawValue)").tag(Optional(account.id))
                        }
                    }
                }

                if mode == .creditCharge || mode == .creditRepayment {
                    Picker("账单周期", selection: statementCycleSelection) {
                        Text(mode == .creditCharge ? "自动匹配" : "选择账单周期").tag(Optional<String>.none)
                        ForEach(openStatementCycles) { cycle in
                            Text("\(FinanceFormatter.shortDate(cycle.statementDate)) · \(FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency))")
                                .tag(Optional(cycle.id))
                        }
                    }
                }

                if mode.categoryType != nil {
                    Picker(mode == .income ? "收入分类" : "支出分类", selection: categorySelection) {
                        Text("选择分类").tag(Optional<String>.none)
                        ForEach(availableCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }

                    HStack {
                        TextField("新分类名称", text: $newCategoryName)
                        Button("创建分类") {
                            Task { await createCategory() }
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                TextField("备注", text: $note, axis: .vertical)
                    .lineLimit(2...4)

                if mode.supportsReimbursement {
                    Toggle("可报销", isOn: $isReimbursable)
                    if isReimbursable {
                        TextField("报销方", text: $reimbursementPayer)
                        DatePicker("预计到账", selection: $reimbursementExpectedDate, displayedComponents: .date)
                    }
                }
            }

            if let warningMessage {
                Text(warningMessage)
                    .font(.caption)
                    .foregroundStyle(FinanceTokens.State.warning)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(FinanceTokens.State.warning)
                    .font(.caption)
            }

            if let missing = missingFieldSummary {
                Text(missing)
                    .font(.caption)
                    .foregroundStyle(FinanceTokens.State.warning)
            }

            HStack {
                Spacer()
                Button("取消") {
                    environment.isShowingNewEntrySheet = false
                }
                Button("创建") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(22)
        .task {
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
            try? await environment.creditViewModel.refresh()
        }
    }

    private var balanceAccountSelection: Binding<String?> {
        Binding(
            get: { selectedBalanceAccountID ?? balanceAccounts.first?.id },
            set: { selectedBalanceAccountID = $0 }
        )
    }

    private var creditAccountSelection: Binding<String?> {
        Binding(
            get: { selectedCreditAccountID ?? creditAccounts.first?.id },
            set: {
                selectedCreditAccountID = $0
                selectedStatementCycleID = nil
            }
        )
    }

    private var statementCycleSelection: Binding<String?> {
        Binding(
            get: { selectedStatementCycleID },
            set: { selectedStatementCycleID = $0 }
        )
    }

    private var categorySelection: Binding<String?> {
        Binding(
            get: {
                if let selectedCategoryID, availableCategories.contains(where: { $0.id == selectedCategoryID }) {
                    return selectedCategoryID
                }
                return availableCategories.first?.id
            },
            set: { selectedCategoryID = $0 }
        )
    }

    private var warningMessage: String? {
        if mode.usesBalanceAccount && balanceAccounts.isEmpty {
            return "请先创建一个余额账户。"
        }
        if mode.usesCreditAccount && creditAccounts.isEmpty {
            return "请先创建一个信用账户。"
        }
        if mode == .creditRepayment && openStatementCycles.isEmpty {
            return "信用还款需要选择一个未结清的账单周期。"
        }
        if mode.categoryType != nil && availableCategories.isEmpty {
            return "请先创建一个\(mode == .income ? "收入" : "支出")分类，或点上面的创建分类。"
        }
        return nil
    }

    private var canSubmit: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Decimal(string: amount) != nil else {
            return false
        }
        if mode.usesBalanceAccount && balanceAccountSelection.wrappedValue == nil {
            return false
        }
        if mode.usesCreditAccount && creditAccountSelection.wrappedValue == nil {
            return false
        }
        if mode.categoryType != nil && categorySelection.wrappedValue == nil {
            return false
        }
        if mode == .creditRepayment && selectedStatementCycleID == nil {
            return false
        }
        return true
    }

    /// Mirrors `canSubmit` and returns a "缺少：…" hint listing each
    /// missing field in Chinese, or nil if the form is ready.
    private var missingFieldSummary: String? {
        if canSubmit { return nil }
        var missing: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("标题")
        }
        if Decimal(string: amount) == nil {
            missing.append("金额")
        }
        if mode.usesBalanceAccount && balanceAccountSelection.wrappedValue == nil {
            missing.append("余额账户")
        }
        if mode.usesCreditAccount && creditAccountSelection.wrappedValue == nil {
            missing.append("信用账户")
        }
        if mode.categoryType != nil && categorySelection.wrappedValue == nil {
            missing.append("分类")
        }
        if mode == .creditRepayment && selectedStatementCycleID == nil {
            missing.append("信用账单周期")
        }
        if missing.isEmpty { return nil }
        return "缺少：" + missing.joined(separator: "、")
    }

    private func createCategory() async {
        guard let categoryType = mode.categoryType else { return }
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await environment.entriesViewModel.createCategory(
                CategoryCreateRequest(
                    name: name,
                    type: categoryType,
                    parentId: nil
                )
            )
            selectedCategoryID = availableCategories.first { $0.name == name }?.id ?? availableCategories.first?.id
            newCategoryName = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard let decimalAmount = Decimal(string: amount),
              let accountID = selectedAccountID else {
            return
        }

        let decimal = DecimalValue(decimalAmount)
        let noteValue = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        let categoryLines: [EntryCategoryLineCreateRequest]
        if let direction = mode.categoryDirection,
           let categoryID = categorySelection.wrappedValue {
            categoryLines = [
                EntryCategoryLineCreateRequest(
                    categoryId: categoryID,
                    direction: direction,
                    amount: decimal,
                    currency: .cny,
                    exchangeRateId: nil,
                    convertedCnyAmount: decimal,
                    reimbursableFlag: isReimbursable && mode.supportsReimbursement,
                    reimbursementPayer: isReimbursable && mode.supportsReimbursement ? reimbursementPayer : nil,
                    reimbursementExpectedDate: isReimbursable && mode.supportsReimbursement ? reimbursementExpectedDate : nil,
                    reimbursementStatus: isReimbursable && mode.supportsReimbursement ? "reimbursable" : nil,
                    note: nil
                )
            ]
        } else {
            categoryLines = []
        }

        let request = EntryCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            status: status,
            note: noteValue,
            categoryLines: categoryLines,
            accountMovements: [
                AccountMovementCreateRequest(
                    accountId: accountID,
                    statementCycleId: selectedStatementCycleID,
                    movementType: mode.movementType,
                    amount: decimal,
                    currency: .cny,
                    exchangeRateId: nil,
                    convertedCnyAmount: decimal,
                    note: nil
                )
            ]
        )

        do {
            try await environment.entriesViewModel.createEntry(request)
            try await environment.accountsViewModel.refresh()
            try await environment.dashboardViewModel.refresh()
            try await environment.reimbursementsViewModel.refresh()
            try await environment.creditViewModel.refresh()
            try await environment.reportsViewModel.refresh()
            try await environment.cashFlowViewModel.refresh()
            environment.isShowingNewEntrySheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var selectedAccountID: String? {
        mode.usesCreditAccount ? creditAccountSelection.wrappedValue : balanceAccountSelection.wrappedValue
    }
}
