import SwiftUI

struct EntriesView: View {
    @Bindable var environment: AppEnvironment
    @State private var statusFilter = "all"
    @State private var confirmation: ConfirmAction?

    private var filteredEntries: [EntryDTO] {
        let entries = statusFilter == "all" ? environment.entriesViewModel.entries : environment.entriesViewModel.entries.filter { $0.status.rawValue == statusFilter }
        guard !environment.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return entries
        }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(environment.searchText)
                || ($0.note?.localizedCaseInsensitiveContains(environment.searchText) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "记账", subtitle: "单笔记录、分类拆分和账户流水")
            HStack(spacing: 10) {
                Picker("状态", selection: $statusFilter) {
                    Text("全部").tag("all")
                    Text("草稿").tag("draft")
                    Text("已确认").tag("confirmed")
                    Text("已作废").tag("voided")
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Button {
                    environment.beginNewEntry()
                } label: {
                    Label("新建记录", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await createQuickExpenseCategory() }
                } label: {
                    Label("补一个支出分类", systemImage: "tag")
                }
                .disabled(environment.entriesViewModel.expenseCategories.contains(where: { $0.name == "日常支出" }))

                Spacer()
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
                List(filteredEntries, selection: Binding(
                    get: {
                        if case .entry(let entry) = environment.inspectorSelection {
                            return entry.id
                        }
                        return nil
                    },
                    set: { id in
                        guard let id, let entry = environment.entriesViewModel.entries.first(where: { $0.id == id }) else { return }
                        environment.inspectorSelection = .entry(entry)
                    }
                )) { entry in
                    EntryRow(entry: entry, accounts: environment.accountsViewModel.accounts, categories: environment.entriesViewModel.categories)
                        .tag(entry.id)
                        .contextMenu {
                            if entry.status == .draft {
                                Button("确认") { confirm(entry, operation: "confirm") }
                            }
                            if entry.status != .voided {
                                Button("作废", role: .destructive) { confirm(entry, operation: "void") }
                            }
                        }
                }
                .listStyle(.inset)
            }

            if let message = environment.entriesViewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(24)
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
                    try? await environment.accountsViewModel.refresh()
                    try? await environment.dashboardViewModel.refresh()
                    try? await environment.reimbursementsViewModel.refresh()
                    try? await environment.creditViewModel.refresh()
                    try? await environment.reportsViewModel.refresh()
                } catch {
                    environment.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct EntryRow: View {
    let entry: EntryDTO
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]

    private var primaryLine: EntryCategoryLineDTO? {
        entry.categoryLines.first
    }

    private var primaryMovement: AccountMovementDTO? {
        entry.accountMovements.first
    }

    private var accountName: String {
        guard let movement = primaryMovement,
              let account = accounts.first(where: { $0.id == movement.accountId }) else {
            return "未匹配账户"
        }
        return account.name
    }

    private var categoryName: String {
        guard let line = primaryLine,
              let category = categories.first(where: { $0.id == line.categoryId }) else {
            return "未分类"
        }
        return category.name
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.status == .confirmed ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(entry.status == .confirmed ? FinanceColor.income : FinanceColor.pending)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.title)
                        .font(.headline)
                    StatusTag(title: entry.status.title, style: entry.status == .confirmed ? .confirmed : .draft)
                }
                Text("\(FinanceFormatter.shortDate(entry.date)) · \(accountName) · \(categoryName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let primaryLine {
                MoneyText(amount: primaryLine.amount, currency: primaryLine.currency, convertedCNY: primaryLine.convertedCnyAmount)
            }
        }
        .padding(.vertical, 6)
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
                    .foregroundStyle(.orange)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.orange)
                    .font(.caption)
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
            try? await environment.reimbursementsViewModel.refresh()
            try? await environment.creditViewModel.refresh()
            try? await environment.reportsViewModel.refresh()
            try? await environment.cashFlowViewModel.refresh()
            environment.isShowingNewEntrySheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var selectedAccountID: String? {
        mode.usesCreditAccount ? creditAccountSelection.wrappedValue : balanceAccountSelection.wrappedValue
    }
}
