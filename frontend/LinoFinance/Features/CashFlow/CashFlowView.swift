import SwiftUI

struct CashFlowView: View {
    @Bindable var environment: AppEnvironment
    @State private var confirmation: ConfirmAction?

    private var filteredItems: [CashFlowItemDTO] {
        let search = environment.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return environment.cashFlowViewModel.items }
        return environment.cashFlowViewModel.items.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.cashFlowType.financeStatusTitle.localizedCaseInsensitiveContains(search)
        }
    }

    private var pressureWindows: [CashFlowPressureWindowDTO] {
        environment.reportsViewModel.bundle?.cashFlow.windows ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "现金流", subtitle: "未来事件、预计收支和正式结算")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(pressureWindows.prefix(3)) { window in
                    ToolbarPill(
                        title: "未来 \(window.days) 天净额",
                        value: FinanceFormatter.money(window.netCny),
                        tint: window.netCny.value < 0 ? FinanceColor.expense : FinanceColor.income
                    )
                }
                if pressureWindows.isEmpty {
                    ToolbarPill(title: "未来 30 天", value: "等待报表", tint: FinanceColor.pending)
                    ToolbarPill(title: "预计进账", value: FinanceFormatter.money(DecimalValue(0)), tint: FinanceColor.income)
                    ToolbarPill(title: "预计出账", value: FinanceFormatter.money(DecimalValue(0)), tint: FinanceColor.expense)
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
                    CashFlowRow(item: item, accounts: environment.accountsViewModel.accounts)
                        .tag(item.id)
                        .contextMenu {
                            Button("确认发生") { confirm(item, operation: "confirm") }
                            if item.direction != "transfer" {
                                Button("结算为正式记录") { confirm(item, operation: "settle") }
                            }
                            Button("取消", role: .destructive) { confirm(item, operation: "cancel") }
                        }
                }
                .listStyle(.inset)
            }

            if let message = environment.cashFlowViewModel.errorMessage {
                ErrorBanner(message: message)
            }
        }
        .padding(24)
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
        let title: String
        let message: String
        let confirmTitle: String
        let role: ButtonRole?
        switch operation {
        case "confirm":
            title = "确认现金流已发生？"
            message = "这会把预计现金流改为已确认，但不会直接改变账户余额。"
            confirmTitle = "确认发生"
            role = nil
        case "settle":
            title = "结算为正式记录？"
            message = "这会创建一条正式记账记录，并影响账户余额。需要现金流已有关联账户和分类。"
            confirmTitle = "结算"
            role = nil
        default:
            title = "取消现金流？"
            message = "取消后此现金流不再计入未来压力。"
            confirmTitle = "取消现金流"
            role = .destructive
        }
        confirmation = ConfirmAction(title: title, message: message, confirmTitle: confirmTitle, role: role) {
            Task { await perform(item, operation: operation) }
        }
    }

    private func perform(_ item: CashFlowItemDTO, operation: String) async {
        do {
            switch operation {
            case "confirm":
                try await environment.cashFlowViewModel.confirm(item.id)
            case "settle":
                try await settle(item)
            default:
                try await environment.cashFlowViewModel.cancel(item.id)
            }
            try? await environment.dashboardViewModel.refresh()
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
            try? await environment.reportsViewModel.refresh()
        } catch {
            environment.cashFlowViewModel.errorMessage = error.localizedDescription
            environment.lastErrorMessage = error.localizedDescription
        }
    }

    private func settle(_ item: CashFlowItemDTO) async throws {
        guard item.direction != "transfer" else {
            throw APIError.badStatus(400, "转账现金流请通过记账里的信用还款流程结算")
        }
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
}

private struct CashFlowRow: View {
    let item: CashFlowItemDTO
    let accounts: [AccountDTO]

    private var tint: Color {
        item.direction == "inflow" ? FinanceColor.income : FinanceColor.expense
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.direction == "inflow" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                    StatusTag(status: item.status)
                    StatusTag(title: item.cashFlowType.financeStatusTitle, style: .expected)
                }
                Text("\(FinanceFormatter.mediumDate(item.expectedDate)) · \(accountName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MoneyText(amount: item.amount, currency: item.currency, convertedCNY: item.convertedCnyAmount, prominence: .headline)
        }
        .padding(.vertical, 6)
    }

    private var accountName: String {
        guard let accountId = item.accountId,
              let account = accounts.first(where: { $0.id == accountId }) else {
            return "未关联账户"
        }
        return account.name
    }
}

struct NewCashFlowSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var title = ""
    @State private var amount = ""
    @State private var expectedDate = Date()
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Decimal(string: amount) == nil)
            }
        }
        .padding(22)
        .task {
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
        }
    }

    private var accountSelection: Binding<String?> {
        Binding(get: { accountId }, set: { accountId = $0 })
    }

    private var categorySelection: Binding<String?> {
        Binding(get: { categoryId }, set: { categoryId = $0 })
    }

    private func submit() async {
        guard let decimal = Decimal(string: amount) else { return }
        let converted = DecimalValue(decimal)
        let request = CashFlowItemCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            direction: direction,
            cashFlowType: cashFlowType,
            amount: converted,
            currency: .cny,
            exchangeRateId: nil,
            convertedCnyAmount: converted,
            expectedDate: expectedDate,
            accountId: accountId,
            categoryId: categoryId,
            recurrenceRule: nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            try await environment.cashFlowViewModel.create(request)
            try? await environment.reportsViewModel.refresh()
            environment.isShowingNewCashFlowSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
