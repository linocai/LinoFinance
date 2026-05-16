import SwiftUI

struct CreditView: View {
    @Bindable var environment: AppEnvironment
    @State private var confirmation: ConfirmAction?

    private var creditAccounts: [AccountDTO] {
        environment.accountsViewModel.accounts.creditAccounts
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "信用", subtitle: "信用卡、账单周期、分期和订阅")

                HStack(spacing: 10) {
                    Button {
                        environment.isShowingNewStatementCycleSheet = true
                    } label: {
                        Label("新建账单周期", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        environment.beginNewEntry()
                    } label: {
                        Label("信用消费 / 还款", systemImage: "creditcard")
                    }

                    Button {
                        environment.isShowingNewInstallmentSheet = true
                    } label: {
                        Label("新建分期", systemImage: "rectangle.stack.badge.plus")
                    }

                    Button {
                        environment.isShowingNewSubscriptionSheet = true
                    } label: {
                        Label("新建订阅", systemImage: "repeat")
                    }
                    Spacer()
                }

                if creditAccounts.isEmpty {
                    EmptyState(
                        title: "还没有信用账户",
                        message: "先在账户模块创建信用账户，再创建账单周期和还款计划。",
                        systemImage: "creditcard.trianglebadge.exclamationmark",
                        actionTitle: "新建账户",
                        action: environment.beginNewAccount
                    )
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(creditAccounts) { account in
                            Button {
                                environment.inspectorSelection = .account(account)
                            } label: {
                                CreditAccountCard(account: account, cycles: environment.creditViewModel.cycles)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                FinancePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("账单周期")
                            .font(.headline)
                        if environment.creditViewModel.cycles.isEmpty {
                            EmptyState(title: "还没有账单周期", message: "账单周期会承载信用消费和还款。", systemImage: "calendar")
                        } else {
                            ForEach(environment.creditViewModel.cycles) { cycle in
                                CreditCycleRow(cycle: cycle, accountName: accountName(cycle.creditAccountId))
                                    .contentShape(Rectangle())
                                    .onTapGesture { environment.inspectorSelection = .creditCycle(cycle) }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    FinancePanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("分期计划")
                                .font(.headline)
                            ForEach(environment.creditViewModel.installmentPlans) { plan in
                                InstallmentRow(plan: plan, accountName: accountName(plan.creditAccountId))
                                    .contentShape(Rectangle())
                                    .onTapGesture { environment.inspectorSelection = .installment(plan) }
                                    .contextMenu {
                                        Button("标记还清") { confirmInstallment(plan, early: false) }
                                        Button("提前结清") { confirmInstallment(plan, early: true) }
                                        Button("取消", role: .destructive) { confirmInstallmentCancel(plan) }
                                    }
                            }
                            if environment.creditViewModel.installmentPlans.isEmpty {
                                EmptyState(title: "暂无分期", message: "从已确认信用消费创建分期计划。", systemImage: "rectangle.stack")
                            }
                        }
                    }

                    FinancePanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("订阅规则")
                                .font(.headline)
                            ForEach(environment.creditViewModel.subscriptionRules) { rule in
                                SubscriptionRow(rule: rule)
                                    .contentShape(Rectangle())
                                    .onTapGesture { environment.inspectorSelection = .subscription(rule) }
                                    .contextMenu {
                                        if rule.status == "active" {
                                            Button("暂停") { confirmSubscription(rule, operation: "pause") }
                                        } else if rule.status == "paused" {
                                            Button("恢复") { confirmSubscription(rule, operation: "resume") }
                                        }
                                        Button("生成下次现金流") { confirmSubscription(rule, operation: "generate") }
                                        Button("取消", role: .destructive) { confirmSubscription(rule, operation: "cancel") }
                                    }
                            }
                            if environment.creditViewModel.subscriptionRules.isEmpty {
                                EmptyState(title: "暂无订阅", message: "创建周期性扣款后会自动生成未来现金流。", systemImage: "repeat")
                            }
                        }
                    }
                }

                if let message = environment.creditViewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .moduleFrame()
        .task {
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
            try? await environment.creditViewModel.refresh()
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

    private func accountName(_ id: String) -> String {
        environment.accountsViewModel.accounts.first { $0.id == id }?.name ?? "未知账户"
    }

    private func confirmInstallment(_ plan: InstallmentPlanDTO, early: Bool) {
        confirmation = ConfirmAction(
            title: early ? "提前结清分期？" : "标记分期已还清？",
            message: "这会取消后续未发生的分期现金流。",
            confirmTitle: early ? "提前结清" : "标记还清",
            role: nil
        ) {
            Task { try? await environment.creditViewModel.markInstallmentPaidOff(plan.id, early: early) }
        }
    }

    private func confirmInstallmentCancel(_ plan: InstallmentPlanDTO) {
        confirmation = ConfirmAction(title: "取消分期计划？", message: "取消后会取消未发生的分期现金流。", confirmTitle: "取消分期", role: .destructive) {
            Task { try? await environment.creditViewModel.cancelInstallment(plan.id) }
        }
    }

    private func confirmSubscription(_ rule: SubscriptionRuleDTO, operation: String) {
        let title = switch operation {
        case "pause": "暂停订阅规则？"
        case "resume": "恢复订阅规则？"
        case "generate": "生成下次现金流？"
        default: "取消订阅规则？"
        }
        confirmation = ConfirmAction(title: title, message: "操作会同步到本地 API。", confirmTitle: title.replacingOccurrences(of: "？", with: ""), role: operation == "cancel" ? .destructive : nil) {
            Task {
                switch operation {
                case "pause": try? await environment.creditViewModel.pauseSubscription(rule.id)
                case "resume": try? await environment.creditViewModel.resumeSubscription(rule.id)
                case "generate": try? await environment.creditViewModel.generateNextSubscription(rule.id)
                default: try? await environment.creditViewModel.cancelSubscription(rule.id)
                }
            }
        }
    }
}

private struct CreditAccountCard: View {
    let account: AccountDTO
    let cycles: [CreditStatementCycleDTO]

    private var nextCycle: CreditStatementCycleDTO? {
        cycles.filter { $0.creditAccountId == account.id && $0.status != "paid" && $0.status != "closed" }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(FinanceColor.credit)
                Spacer()
                StatusTag(title: account.status.financeStatusTitle, style: .confirmed)
            }
            Text(account.name)
                .font(.headline)
            MoneyText(amount: account.currentLiability, currency: account.currency, prominence: .title3.weight(.semibold))
            HStack {
                Text("账单日 \(account.statementDay.map(String.init) ?? "-")")
                Spacer()
                Text("还款日 \(account.dueDay.map(String.init) ?? "-")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let nextCycle {
                Text("下次应还 \(FinanceFormatter.shortDate(nextCycle.dueDate)) · \(FinanceFormatter.money(nextCycle.remainingAmount, currency: nextCycle.currency))")
                    .font(.caption)
                    .foregroundStyle(FinanceColor.credit)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CreditCycleRow: View {
    let cycle: CreditStatementCycleDTO
    let accountName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(accountName)
                    .font(.headline)
                Text("\(FinanceFormatter.shortDate(cycle.cycleStartDate)) - \(FinanceFormatter.shortDate(cycle.cycleEndDate)) · 到期 \(FinanceFormatter.shortDate(cycle.dueDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusTag(status: cycle.status)
            MoneyText(amount: cycle.remainingAmount, currency: cycle.currency, prominence: .headline)
        }
        .padding(.vertical, 6)
    }
}

private struct InstallmentRow: View {
    let plan: InstallmentPlanDTO
    let accountName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(accountName)
                    .font(.headline)
                Text("\(plan.numberOfPayments) 期 · \(FinanceFormatter.shortDate(plan.startDate)) - \(FinanceFormatter.shortDate(plan.endDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusTag(status: plan.status)
            MoneyText(amount: plan.paymentAmount, currency: plan.currency)
        }
        .padding(.vertical, 6)
    }
}

private struct SubscriptionRow: View {
    let rule: SubscriptionRuleDTO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title)
                    .font(.headline)
                Text("\(rule.billingInterval.financeStatusTitle) · 下次 \(rule.nextChargeDate.map(FinanceFormatter.shortDate) ?? "未排期")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusTag(status: rule.status)
            MoneyText(amount: rule.amount, currency: rule.currency)
        }
        .padding(.vertical, 6)
    }
}

struct NewStatementCycleSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var accountId: String?
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var statementDate = Date()
    @State private var dueDate = Date()
    @State private var statementAmount = "0"
    @State private var minimumPayment = "0"
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建账单周期")
                .font(.title2.weight(.semibold))
            Form {
                Picker("信用账户", selection: accountSelection) {
                    ForEach(environment.accountsViewModel.accounts.creditAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                DatePicker("周期开始", selection: $startDate, displayedComponents: .date)
                DatePicker("周期结束", selection: $endDate, displayedComponents: .date)
                DatePicker("出账日", selection: $statementDate, displayedComponents: .date)
                DatePicker("还款日", selection: $dueDate, displayedComponents: .date)
                TextField("账单金额", text: $statementAmount)
                TextField("最低还款", text: $minimumPayment)
                TextField("备注", text: $note)
            }
            if let errorMessage { ErrorBanner(message: errorMessage) }
            HStack {
                Spacer()
                Button("取消") { environment.isShowingNewStatementCycleSheet = false }
                Button("创建") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(accountSelection.wrappedValue == nil)
            }
        }
        .padding(22)
        .task { try? await environment.accountsViewModel.refresh() }
    }

    private var accountSelection: Binding<String?> {
        Binding(get: { accountId ?? environment.accountsViewModel.accounts.creditAccounts.first?.id }, set: { accountId = $0 })
    }

    private func submit() async {
        guard let account = environment.accountsViewModel.accounts.first(where: { $0.id == accountSelection.wrappedValue }) else { return }
        let request = CreditStatementCycleCreateRequest(
            creditAccountId: account.id,
            cycleStartDate: startDate,
            cycleEndDate: endDate,
            statementDate: statementDate,
            dueDate: dueDate,
            currency: account.currency,
            statementAmount: DecimalValue(Decimal(string: statementAmount) ?? 0),
            minimumPayment: DecimalValue(Decimal(string: minimumPayment) ?? 0),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            try await environment.creditViewModel.createCycle(request)
            environment.isShowingNewStatementCycleSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NewInstallmentPlanSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var entryId: String?
    @State private var accountId: String?
    @State private var totalAmount = ""
    @State private var numberOfPayments = 3
    @State private var paymentAmount = ""
    @State private var startDate = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建分期")
                .font(.title2.weight(.semibold))
            Form {
                Picker("信用消费记录", selection: entrySelection) {
                    ForEach(environment.entriesViewModel.entries) { entry in
                        Text(entry.title).tag(Optional(entry.id))
                    }
                }
                Picker("信用账户", selection: accountSelection) {
                    ForEach(environment.accountsViewModel.accounts.creditAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                TextField("总金额", text: $totalAmount)
                Stepper("期数 \(numberOfPayments)", value: $numberOfPayments, in: 1...36)
                TextField("每期金额（可空）", text: $paymentAmount)
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                TextField("备注", text: $note)
            }
            if let errorMessage { ErrorBanner(message: errorMessage) }
            HStack {
                Spacer()
                Button("取消") { environment.isShowingNewInstallmentSheet = false }
                Button("创建") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(entrySelection.wrappedValue == nil || accountSelection.wrappedValue == nil || Decimal(string: totalAmount) == nil)
            }
        }
        .padding(22)
        .task {
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
        }
    }

    private var entrySelection: Binding<String?> {
        Binding(get: { entryId ?? environment.entriesViewModel.entries.first?.id }, set: { entryId = $0 })
    }

    private var accountSelection: Binding<String?> {
        Binding(get: { accountId ?? environment.accountsViewModel.accounts.creditAccounts.first?.id }, set: { accountId = $0 })
    }

    private func submit() async {
        guard let entryId = entrySelection.wrappedValue,
              let account = environment.accountsViewModel.accounts.first(where: { $0.id == accountSelection.wrappedValue }),
              let total = Decimal(string: totalAmount) else { return }
        let payment = Decimal(string: paymentAmount)
        let request = InstallmentPlanCreateRequest(
            linkedEntryId: entryId,
            creditAccountId: account.id,
            totalAmount: DecimalValue(total),
            currency: account.currency,
            numberOfPayments: numberOfPayments,
            paymentAmount: payment.map(DecimalValue.init),
            startDate: startDate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        do {
            try await environment.creditViewModel.createInstallmentPlan(request)
            environment.isShowingNewInstallmentSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NewSubscriptionSheet: View {
    @Bindable var environment: AppEnvironment
    @State private var title = ""
    @State private var amount = ""
    @State private var interval = "monthly"
    @State private var billingDay = 1
    @State private var startDate = Date()
    @State private var accountId: String?
    @State private var categoryId: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建订阅")
                .font(.title2.weight(.semibold))
            Form {
                TextField("标题", text: $title)
                TextField("金额", text: $amount)
                Picker("周期", selection: $interval) {
                    Text("每周").tag("weekly")
                    Text("每月").tag("monthly")
                    Text("每年").tag("yearly")
                }
                Stepper("扣款日 \(billingDay)", value: $billingDay, in: 1...31)
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                Picker("账户", selection: accountSelection) {
                    Text("不关联").tag(Optional<String>.none)
                    ForEach(environment.accountsViewModel.accounts.balanceAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker("分类", selection: categorySelection) {
                    Text("不关联").tag(Optional<String>.none)
                    ForEach(environment.entriesViewModel.expenseCategories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            }
            if let errorMessage { ErrorBanner(message: errorMessage) }
            HStack {
                Spacer()
                Button("取消") { environment.isShowingNewSubscriptionSheet = false }
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
        let request = SubscriptionRuleCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: DecimalValue(decimal),
            currency: .cny,
            accountId: accountId,
            categoryId: categoryId,
            billingInterval: interval,
            billingDay: interval == "weekly" ? nil : billingDay,
            startDate: startDate,
            nextChargeDate: startDate
        )
        do {
            try await environment.creditViewModel.createSubscription(request)
            try? await environment.cashFlowViewModel.refresh()
            environment.isShowingNewSubscriptionSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
