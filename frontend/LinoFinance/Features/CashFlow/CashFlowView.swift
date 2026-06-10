import SwiftUI

extension CashFlowItemDTO {
    /// Whether the generic "结算" (settle) action may be offered in the UI.
    /// Transfers settle through the credit-repayment flow, and
    /// reimbursement-linked receivables settle only through the claim's
    /// mark-received action — the backend rejects a direct settle on either
    /// (audit 1.3), so the entry point is hidden here too.
    var canShowSettleAction: Bool {
        direction != "transfer" && linkedReimbursementId == nil
    }
}

struct CashFlowView: View {
    @Bindable var environment: AppEnvironment
    @State private var confirmation: ConfirmAction?

    private var filteredItems: [CashFlowItemDTO] {
        let search = environment.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = environment.cashFlowViewModel.items
        let matched: [CashFlowItemDTO]
        if search.isEmpty {
            matched = base
        } else {
            matched = base.filter {
                $0.title.localizedCaseInsensitiveContains(search)
                    || $0.cashFlowType.financeStatusTitle.localizedCaseInsensitiveContains(search)
            }
        }
        // Active rows first (expected/confirmed), settled drops to the
        // bottom so the user's eye stays on what still needs action.
        // Within each bucket, preserve the server's expected_date order.
        return matched.sorted { lhs, rhs in
            let lhsDone = lhs.status == "settled"
            let rhsDone = rhs.status == "settled"
            if lhsDone != rhsDone { return !lhsDone }
            return lhs.expectedDate < rhs.expectedDate
        }
    }

    private var pressureWindows: [CashFlowPressureWindowDTO] {
        environment.reportsViewModel.bundle?.cashFlow.windows ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "现金流", subtitle: "未来事件、预计收支和正式结算")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(pressureWindows.prefix(3)) { window in
                    ToolbarPill(
                        title: "未来 \(window.days) 天净额",
                        value: FinanceFormatter.money(window.netCny),
                        tint: window.netCny.value < 0 ? FinanceTokens.State.expense : FinanceTokens.State.income
                    )
                }
                if pressureWindows.isEmpty {
                    ToolbarPill(title: "未来 30 天", value: "等待报表", tint: FinanceTokens.State.pending)
                    ToolbarPill(title: "预计进账", value: FinanceFormatter.money(DecimalValue(0)), tint: FinanceTokens.State.income)
                    ToolbarPill(title: "预计出账", value: FinanceFormatter.money(DecimalValue(0)), tint: FinanceTokens.State.expense)
                }
            }

            HStack(spacing: 10) {
                Button {
                    environment.beginNewCashFlow()
                } label: {
                    Label("新建现金流", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }

            if environment.cashFlowViewModel.items.isEmpty {
                EmptyState(
                    title: "还没有现金流",
                    message: "创建订阅、报销或一次性预计收支后，这里会显示未来压力。",
                    systemImage: "arrow.left.arrow.right.circle",
                    actionTitle: "新建现金流",
                    action: environment.beginNewCashFlow
                )
            } else {
                List(filteredItems, selection: Binding(
                    get: {
                        if case .cashFlow(let item) = environment.inspectorSelection {
                            return item.id
                        }
                        return nil
                    },
                    set: { id in
                        guard let id, let item = environment.cashFlowViewModel.items.first(where: { $0.id == id }) else { return }
                        environment.inspectorSelection = .cashFlow(item)
                    }
                )) { item in
                    HStack {
                        CashFlowRow(item: item, accounts: environment.accountsViewModel.accounts)
                        CashFlowActionMenu(item: item, confirm: confirm)
                    }
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture { environment.inspectorSelection = .cashFlow(item) }
                    .contextMenu {
                        Button("编辑") { confirm(item, operation: "edit") }
                        if item.canShowSettleAction {
                            Button("结算") { confirm(item, operation: "settle") }
                        }
                        Button("取消", role: .destructive) { confirm(item, operation: "cancel") }
                    }
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if item.status == "expected" || item.status == "confirmed" {
                            Button("编辑") { confirm(item, operation: "edit") }
                                .tint(.blue)
                            if item.canShowSettleAction {
                                Button("结算") { confirm(item, operation: "settle") }
                                    .tint(.green)
                            }
                            Button("取消", role: .destructive) {
                                confirm(item, operation: "cancel")
                            }
                        }
                    }
                    #endif
                }
                .listStyle(.inset)
            }

            if let message = environment.cashFlowViewModel.errorMessage {
                ErrorBanner(
                    message: message,
                    onRetry: {
                        Task { try? await environment.cashFlowViewModel.refresh() }
                    },
                    onDismiss: {
                        environment.cashFlowViewModel.errorMessage = nil
                    }
                )
            }
        }
        .padding(FinanceTokens.Spacing.page)
        .moduleFrame()
        .task {
            try? await environment.cashFlowViewModel.refresh()
            try? await environment.reportsViewModel.refresh()
        }
        .alert(confirmation?.title ?? "确认操作", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), presenting: confirmation) { item in
            Button(item.confirmTitle, role: item.role) {
                item.action()
                confirmation = nil
            }
            Button("取消", role: .cancel) {
                confirmation = nil
            }
        } message: { item in
            Text(item.message)
        }
    }

    private func confirm(_ item: CashFlowItemDTO, operation: String) {
        switch operation {
        case "edit":
            // Edit bypasses the confirmation alert and opens the sheet
            // directly — the sheet itself has its own save button.
            environment.beginEditCashFlow(item)
            return
        case "settle":
            confirmation = ConfirmAction(
                title: "结算为正式记录？",
                message: "这会创建一条正式记账记录，并影响账户余额。",
                confirmTitle: "结算",
                role: nil
            ) {
                Task { await perform(item, operation: operation) }
            }
        default:
            confirmation = ConfirmAction(
                title: "取消现金流？",
                message: "取消后此现金流不再计入未来压力。",
                confirmTitle: "取消现金流",
                role: .destructive
            ) {
                Task { await perform(item, operation: operation) }
            }
        }
    }

    private func perform(_ item: CashFlowItemDTO, operation: String) async {
        do {
            switch operation {
            case "settle":
                await attemptSettle(item)
                return
            default:
                try await environment.cashFlowViewModel.cancel(item.id)
            }
            try await refreshAll(environment: environment)
        } catch {
            environment.cashFlowViewModel.errorMessage = error.localizedDescription
            environment.lastErrorMessage = error.localizedDescription
        }
    }

    private func attemptSettle(_ item: CashFlowItemDTO) async {
        if item.direction == "transfer" {
            environment.cashFlowViewModel.errorMessage = "转账现金流请通过记账里的信用还款流程结算"
            return
        }
        if item.linkedReimbursementId != nil {
            // The settle entry points are hidden for these, but guard the path
            // anyway: the backend rejects a direct settle (audit 1.3).
            environment.cashFlowViewModel.errorMessage = "报销关联现金流请通过报销中心的「标记到账」结算"
            return
        }
        if item.accountId != nil, item.categoryId != nil {
            do {
                try await runSettle(environment: environment, for: item)
                try await refreshAll(environment: environment)
            } catch {
                environment.cashFlowViewModel.errorMessage = error.localizedDescription
            }
        } else {
            environment.beginSettleCashFlow(item)
        }
    }
}

/// Build a `CashFlowSettleRequest` from a fully-linked cash flow item and
/// send it through the view model. Shared by `CashFlowView.attemptSettle`
/// (fast path) and `SettleCompletionSheet.submit` (post-PATCH path).
@MainActor
func runSettle(environment: AppEnvironment, for item: CashFlowItemDTO) async throws {
    guard let accountId = item.accountId, let categoryId = item.categoryId else {
        throw APIError.badStatus(400, "结算需要现金流已关联账户和分类")
    }
    let isInflow = item.direction == "inflow"
    let entry = EntryCreateRequest(
        title: item.title,
        date: Date(),
        status: .confirmed,
        note: item.note,
        categoryLines: [
            EntryCategoryLineCreateRequest(
                categoryId: categoryId,
                direction: isInflow ? .income : .expense,
                amount: item.amount,
                currency: item.currency,
                exchangeRateId: item.exchangeRateId,
                convertedCnyAmount: item.convertedCnyAmount,
                note: item.note
            )
        ],
        accountMovements: [
            AccountMovementCreateRequest(
                accountId: accountId,
                statementCycleId: item.linkedStatementCycleId,
                movementType: isInflow ? .balanceIn : .balanceOut,
                amount: item.amount,
                currency: item.currency,
                exchangeRateId: item.exchangeRateId,
                convertedCnyAmount: item.convertedCnyAmount,
                note: item.note
            )
        ]
    )
    try await environment.cashFlowViewModel.settle(item.id, request: CashFlowSettleRequest(entry: entry))
}

@MainActor
func refreshAll(environment: AppEnvironment) async throws {
    try await environment.dashboardViewModel.refresh()
    try await environment.accountsViewModel.refresh()
    try await environment.entriesViewModel.refresh()
    try await environment.reportsViewModel.refresh()
}

private struct CashFlowRow: View {
    let item: CashFlowItemDTO
    let accounts: [AccountDTO]

    private var isSettled: Bool { item.status == "settled" }

    private var tint: Color {
        if isSettled { return FinanceTokens.Text.tertiary }
        return item.direction == "inflow" ? FinanceTokens.State.income : FinanceTokens.State.expense
    }

    // Settled rows render at ~55% opacity so the whole row visually
    // recedes; the StatusTag + position-at-bottom already carry the
    // semantic, this just makes scanning fast.
    private var rowOpacity: Double { isSettled ? 0.55 : 1.0 }

    var body: some View {
        #if os(iOS)
        HStack(alignment: .top, spacing: 12) {
            directionIcon
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    StatusTag(status: item.status)
                    StatusTag(title: item.cashFlowType.financeStatusTitle, style: .expected)
                }
                Text("\(FinanceFormatter.mediumDate(item.expectedDate)) · \(accountName)")
                    .font(.caption)
                    .foregroundStyle(FinanceTokens.Text.secondary)
                    .lineLimit(2)
                MoneyText(amount: item.amount, currency: item.currency, convertedCNY: item.convertedCnyAmount, prominence: .headline)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .opacity(rowOpacity)
        #else
        HStack(spacing: 12) {
            directionIcon
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                    StatusTag(status: item.status)
                    StatusTag(title: item.cashFlowType.financeStatusTitle, style: .expected)
                }
                Text("\(FinanceFormatter.mediumDate(item.expectedDate)) · \(accountName)")
                    .font(.caption)
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            Spacer()
            MoneyText(amount: item.amount, currency: item.currency, convertedCNY: item.convertedCnyAmount, prominence: .headline)
        }
        .padding(.vertical, 6)
        .opacity(rowOpacity)
        #endif
    }

    private var accountName: String {
        guard let accountId = item.accountId,
              let account = accounts.first(where: { $0.id == accountId }) else {
            return "未关联账户"
        }
        return account.name
    }

    private var directionIcon: some View {
        Image(systemName: item.direction == "inflow" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
            .foregroundStyle(tint)
            .frame(width: 28)
    }
}

private struct CashFlowActionMenu: View {
    let item: CashFlowItemDTO
    let confirm: (CashFlowItemDTO, String) -> Void

    var body: some View {
        Menu {
            Button("编辑") { confirm(item, "edit") }
            if item.canShowSettleAction {
                Button("结算") { confirm(item, "settle") }
            }
            Button("取消", role: .destructive) { confirm(item, "cancel") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
    }
}

struct NewCashFlowSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var title = ""
    @State private var amount = ""
    @State private var expectedDate = Date()
    @State private var recurrenceEndDate = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    @State private var direction = "outflow"
    @State private var cashFlowType = "one_time"
    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建现金流")
                .font(.title2.weight(.semibold))
            Form {
                TextField("标题", text: $title)
                TextField("金额", text: $amount)
                Picker("方向", selection: $direction) {
                    Text("进账").tag("inflow")
                    Text("出账").tag("outflow")
                    Text("转账").tag("transfer")
                }
                Picker("类型", selection: $cashFlowType) {
                    ForEach(["salary", "rent_income", "reimbursement", "subscription", "credit_repayment", "installment", "one_time", "other"], id: \.self) {
                        Text($0.financeStatusTitle).tag($0)
                    }
                }
                DatePicker("预计日期", selection: $expectedDate, displayedComponents: .date)
                if cashFlowType == "salary" {
                    DatePicker("每月重复到", selection: $recurrenceEndDate, displayedComponents: .date)
                    Text("会从预计日期开始，每月生成一条工资进账，直到截止日期所在日。")
                        .font(.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                }
                Picker("账户", selection: accountSelection) {
                    Text("不关联").tag(Optional<String>.none)
                    ForEach(environment.accountsViewModel.accounts.balanceAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker("分类", selection: categorySelection) {
                    Text("不关联").tag(Optional<String>.none)
                    ForEach(environment.entriesViewModel.categories.filter { $0.type == (direction == "inflow" ? .income : .expense) }) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                TextField("备注", text: $note)
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            HStack {
                Spacer()
                Button("取消") { environment.isShowingNewCashFlowSheet = false }
                Button("创建") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parseDecimalAmount(amount) == nil)
            }
        }
        .padding(22)
        .task {
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
        }
        .onChange(of: cashFlowType) { _, newValue in
            if newValue == "salary" {
                direction = "inflow"
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = "工资"
                }
                if recurrenceEndDate < expectedDate {
                    recurrenceEndDate = expectedDate
                }
            }
        }
        .onChange(of: expectedDate) { _, newValue in
            if cashFlowType == "salary", recurrenceEndDate < newValue {
                recurrenceEndDate = newValue
            }
        }
    }

    private var accountSelection: Binding<String?> {
        Binding(get: { accountId }, set: { accountId = $0 })
    }

    private var categorySelection: Binding<String?> {
        Binding(get: { categoryId }, set: { categoryId = $0 })
    }

    private func submit() async {
        guard let decimal = parseDecimalAmount(amount) else { return }
        if cashFlowType == "salary", recurrenceEndDate < expectedDate {
            errorMessage = "工资重复截止日期不能早于首次预计日期"
            return
        }
        let converted = DecimalValue(decimal)
        let requests = cashFlowRequests(amount: converted)
        do {
            try await environment.cashFlowViewModel.create(requests)
            try await environment.reportsViewModel.refresh()
            environment.isShowingNewCashFlowSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cashFlowRequests(amount: DecimalValue) -> [CashFlowItemCreateRequest] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmedNote.isEmpty ? nil : trimmedNote
        let dates = cashFlowType == "salary" ? monthlyDates(from: expectedDate, through: recurrenceEndDate) : [expectedDate]
        let recurrenceRule = cashFlowType == "salary" ? "FREQ=MONTHLY;UNTIL=\(DateFormatter.linoAPIDate.string(from: recurrenceEndDate))" : nil

        return dates.map { date in
            CashFlowItemCreateRequest(
                title: trimmedTitle,
                direction: cashFlowType == "salary" ? "inflow" : direction,
                cashFlowType: cashFlowType,
                amount: amount,
                currency: .cny,
                exchangeRateId: nil,
                convertedCnyAmount: amount,
                expectedDate: date,
                accountId: accountId,
                categoryId: categoryId,
                recurrenceRule: recurrenceRule,
                note: noteValue
            )
        }
    }

    private func monthlyDates(from startDate: Date, through endDate: Date) -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        var current = startDate
        while current <= endDate, dates.count < 120 {
            dates.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
}

struct EditCashFlowSheet: View {
    @Bindable var environment: AppEnvironment
    let initial: CashFlowItemDTO

    @State private var title: String
    @State private var amount: String
    @State private var expectedDate: Date
    @State private var direction: String
    @State private var cashFlowType: String
    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var currency: CurrencyCode
    @State private var exchangeRateId: String?
    @State private var note: String
    @State private var errorMessage: String?
    @State private var submitting = false

    init(environment: AppEnvironment, item: CashFlowItemDTO) {
        self.environment = environment
        self.initial = item
        _title = State(initialValue: item.title)
        _amount = State(initialValue: "\(item.amount.value)")
        _expectedDate = State(initialValue: item.expectedDate)
        _direction = State(initialValue: item.direction)
        _cashFlowType = State(initialValue: item.cashFlowType)
        _accountId = State(initialValue: item.accountId)
        _categoryId = State(initialValue: item.categoryId)
        _currency = State(initialValue: item.currency)
        _exchangeRateId = State(initialValue: item.exchangeRateId)
        _note = State(initialValue: item.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑现金流")
                .font(.title2.weight(.semibold))
            Form {
                TextField("标题", text: $title)
                TextField("金额", text: $amount)
                Picker("方向", selection: $direction) {
                    Text("进账").tag("inflow")
                    Text("出账").tag("outflow")
                    Text("转账").tag("transfer")
                }
                Picker("类型", selection: $cashFlowType) {
                    ForEach(
                        ["salary", "rent_income", "reimbursement", "subscription",
                         "credit_repayment", "installment", "one_time", "other"],
                        id: \.self
                    ) {
                        Text($0.financeStatusTitle).tag($0)
                    }
                }
                DatePicker("预计日期", selection: $expectedDate, displayedComponents: .date)
                Picker("币种", selection: $currency) {
                    ForEach(CurrencyCode.allCases, id: \.self) { code in
                        Text(code.rawValue).tag(code)
                    }
                }
                if currency != .cny {
                    Picker(
                        "汇率",
                        selection: Binding(get: { exchangeRateId }, set: { exchangeRateId = $0 })
                    ) {
                        Text("未指定").tag(Optional<String>.none)
                        ForEach(
                            environment.settingsViewModel.rates.filter { $0.fromCurrency == currency }
                        ) { rate in
                            Text("\(rate.fromCurrency.rawValue) → CNY @ \(rate.rate.value)")
                                .tag(Optional(rate.id))
                        }
                    }
                }
                Picker(
                    "账户",
                    selection: Binding(get: { accountId }, set: { accountId = $0 })
                ) {
                    Text("不关联").tag(Optional<String>.none)
                    ForEach(
                        environment.accountsViewModel.accounts
                            .filter { $0.currency == currency }
                    ) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker(
                    "分类",
                    selection: Binding(get: { categoryId }, set: { categoryId = $0 })
                ) {
                    Text("不关联").tag(Optional<String>.none)
                    ForEach(
                        environment.entriesViewModel.categories
                            .filter { $0.type == (direction == "inflow" ? .income : .expense) }
                    ) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                TextField("备注", text: $note)
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            HStack {
                Spacer()
                Button("取消") {
                    environment.clearEditCashFlowSheet()
                }
                .disabled(submitting)
                Button("保存") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid || submitting)
            }
        }
        .padding(22)
        .task {
            try? await environment.settingsViewModel.refresh()
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
        }
        .onChange(of: currency) { _, newValue in
            // Drop any account that no longer matches the chosen currency.
            if let id = accountId,
               let account = environment.accountsViewModel.accounts.first(where: { $0.id == id }),
               account.currency != newValue {
                accountId = nil
            }
            if newValue == .cny {
                exchangeRateId = nil
            }
        }
    }

    private var isFormValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard parseDecimalAmount(amount) != nil else { return false }
        if currency != .cny && exchangeRateId == nil { return false }
        return true
    }

    private func submit() async {
        guard let decimal = parseDecimalAmount(amount) else { return }
        if currency != .cny && exchangeRateId == nil {
            errorMessage = "缺少 \(currency.rawValue) → CNY 汇率，请到设置中添加"
            return
        }
        submitting = true
        defer { submitting = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CashFlowItemUpdateRequest(
            title: trimmedTitle,
            direction: direction,
            cashFlowType: cashFlowType,
            amount: DecimalValue(decimal),
            currency: currency,
            exchangeRateId: exchangeRateId,
            convertedCnyAmount: nil,
            expectedDate: expectedDate,
            accountId: accountId.map(Nullable.value) ?? .null,
            categoryId: categoryId.map(Nullable.value) ?? .null,
            recurrenceRule: nil,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )

        do {
            try await environment.cashFlowViewModel.update(initial.id, request: request)
            try await environment.dashboardViewModel.refresh()
            try await environment.accountsViewModel.refresh()
            try await environment.entriesViewModel.refresh()
            try await environment.reportsViewModel.refresh()
            environment.clearEditCashFlowSheet()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SettleCompletionSheet: View {
    @Bindable var environment: AppEnvironment
    let item: CashFlowItemDTO

    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var errorMessage: String?
    @State private var submitting = false

    init(environment: AppEnvironment, item: CashFlowItemDTO) {
        self.environment = environment
        self.item = item
        _accountId = State(initialValue: item.accountId)
        _categoryId = State(initialValue: item.categoryId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("结算现金流")
                .font(.title2.weight(.semibold))
            Text(item.title)
                .font(.headline)
            Text("结算前请补齐缺失的账户和分类。")
                .font(.subheadline)
                .foregroundStyle(FinanceTokens.Text.secondary)
            Form {
                Picker(
                    "账户",
                    selection: Binding(get: { accountId }, set: { accountId = $0 })
                ) {
                    Text("请选择").tag(Optional<String>.none)
                    ForEach(
                        environment.accountsViewModel.accounts
                            .filter { $0.currency == item.currency }
                    ) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker(
                    "分类",
                    selection: Binding(get: { categoryId }, set: { categoryId = $0 })
                ) {
                    Text("请选择").tag(Optional<String>.none)
                    ForEach(
                        environment.entriesViewModel.categories
                            .filter { $0.type == (item.direction == "inflow" ? .income : .expense) }
                    ) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            HStack {
                Spacer()
                Button("取消") {
                    environment.clearSettleCashFlowSheet()
                }
                .disabled(submitting)
                Button("结算") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(accountId == nil || categoryId == nil || submitting)
            }
        }
        .padding(22)
        .task {
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
        }
    }

    private func submit() async {
        guard let accountId, let categoryId else { return }
        submitting = true
        defer { submitting = false }
        do {
            let patch = CashFlowItemUpdateRequest(
                accountId: .value(accountId),
                categoryId: .value(categoryId)
            )
            try await environment.cashFlowViewModel.update(item.id, request: patch)
            guard let refreshed = environment.cashFlowViewModel.items.first(where: { $0.id == item.id }) else {
                throw APIError.badStatus(500, "结算失败：现金流已不在列表中")
            }
            try await runSettle(environment: environment, for: refreshed)
            try await refreshAll(environment: environment)
            environment.clearSettleCashFlowSheet()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
