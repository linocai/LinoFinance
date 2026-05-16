import SwiftUI

struct SelectionDetailView: View {
    let selection: InspectorSelection?
    let environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch selection {
            case .account(let account):
                AccountDetail(account: account)
            case .entry(let entry):
                EntryDetail(entry: entry, accounts: environment.accountsViewModel.accounts, categories: environment.entriesViewModel.categories)
            case .cashFlow(let item):
                CashFlowDetail(item: item, accounts: environment.accountsViewModel.accounts, categories: environment.entriesViewModel.categories)
            case .reimbursement(let claim):
                ReimbursementDetail(claim: claim, entries: environment.entriesViewModel.entries, accounts: environment.accountsViewModel.accounts)
            case .creditCycle(let cycle):
                CreditCycleDetail(cycle: cycle, accounts: environment.accountsViewModel.accounts)
            case .installment(let plan):
                InstallmentDetail(plan: plan, accounts: environment.accountsViewModel.accounts, entries: environment.entriesViewModel.entries)
            case .subscription(let rule):
                SubscriptionDetail(rule: rule, accounts: environment.accountsViewModel.accounts, categories: environment.entriesViewModel.categories)
            case .aiPlan(let plan):
                AIPlanDetail(plan: plan)
            case .notification(let rule):
                NotificationRuleDetail(rule: rule)
            case .module(let module):
                ModuleDetail(module: module)
            case .none:
                EmptyState(title: "详情", message: "选择账户、记录或计划后，这里显示详情。", systemImage: "sidebar.right")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AccountDetail: View {
    let account: AccountDTO

    var body: some View {
        DetailSection(title: "账户详情", systemImage: account.type == .credit ? "creditcard.fill" : "wallet.pass.fill", headline: account.name) {
            HStack {
                StatusTag(title: account.type.title, style: account.type == .credit ? .warning : .confirmed)
                StatusTag(status: account.status)
            }
            DetailLine(title: "币种", value: account.currency.rawValue)
            DetailLine(title: "余额", value: FinanceFormatter.money(account.currentBalance, currency: account.currency))
            DetailLine(title: "负债", value: FinanceFormatter.money(account.currentLiability, currency: account.currency))
            if let creditLimit = account.creditLimit {
                DetailLine(title: "信用额度", value: FinanceFormatter.money(creditLimit, currency: account.currency))
            }
            if let statementDay = account.statementDay {
                DetailLine(title: "账单日", value: "\(statementDay) 日")
            }
            if let dueDay = account.dueDay {
                DetailLine(title: "还款日", value: "\(dueDay) 日")
            }
            if let minimumPayment = account.minimumPayment {
                DetailLine(title: "最低还款", value: FinanceFormatter.money(minimumPayment, currency: account.currency))
            }
            DetailNote(account.notes)
        }
    }
}

private struct EntryDetail: View {
    let entry: EntryDTO
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]

    var body: some View {
        DetailSection(title: "记录详情", systemImage: "square.and.pencil", headline: entry.title) {
            StatusTag(title: entry.status.title, style: entry.status == .confirmed ? .confirmed : entry.status == .voided ? .cancelled : .draft)
            DetailLine(title: "日期", value: FinanceFormatter.mediumDate(entry.date))
            DetailLine(title: "创建者", value: entry.createdBy)
            if !entry.categoryLines.isEmpty {
                Divider()
                Text("分类明细").font(.headline)
                ForEach(entry.categoryLines) { line in
                    DetailLine(title: categoryName(line.categoryId), value: FinanceFormatter.money(line.amount, currency: line.currency))
                    if line.reimbursableFlag {
                        StatusTag(title: line.reimbursementStatus?.financeStatusTitle ?? "可报销", style: .ai)
                    }
                }
            }
            if !entry.accountMovements.isEmpty {
                Divider()
                Text("账户流水").font(.headline)
                ForEach(entry.accountMovements) { movement in
                    DetailLine(title: accountName(movement.accountId), value: "\(movement.movementType.rawValue.financeStatusTitle) · \(FinanceFormatter.money(movement.amount, currency: movement.currency))")
                }
            }
            DetailNote(entry.note)
        }
    }

    private func accountName(_ id: String) -> String {
        accounts.first { $0.id == id }?.name ?? "未知账户"
    }

    private func categoryName(_ id: String) -> String {
        categories.first { $0.id == id }?.name ?? "未知分类"
    }
}

private struct CashFlowDetail: View {
    let item: CashFlowItemDTO
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]

    var body: some View {
        DetailSection(title: "现金流详情", systemImage: "arrow.left.arrow.right.circle.fill", headline: item.title) {
            HStack {
                StatusTag(status: item.status)
                StatusTag(status: item.direction)
                StatusTag(status: item.cashFlowType)
            }
            DetailLine(title: "预计日期", value: FinanceFormatter.mediumDate(item.expectedDate))
            DetailLine(title: "金额", value: FinanceFormatter.money(item.amount, currency: item.currency))
            DetailLine(title: "账户", value: item.accountId.flatMap(accountName) ?? "未关联")
            DetailLine(title: "分类", value: item.categoryId.flatMap(categoryName) ?? "未关联")
            if let recurrenceRule = item.recurrenceRule {
                DetailLine(title: "重复规则", value: recurrenceRule)
            }
            DetailNote(item.note)
        }
    }

    private func accountName(_ id: String) -> String? {
        accounts.first { $0.id == id }?.name
    }

    private func categoryName(_ id: String) -> String? {
        categories.first { $0.id == id }?.name
    }
}

private struct ReimbursementDetail: View {
    let claim: ReimbursementClaimDTO
    let entries: [EntryDTO]
    let accounts: [AccountDTO]

    var body: some View {
        DetailSection(title: "报销详情", systemImage: "arrow.uturn.left.circle.fill", headline: entryTitle) {
            StatusTag(status: claim.status)
            DetailLine(title: "付款方", value: claim.payer)
            DetailLine(title: "预计到账", value: FinanceFormatter.mediumDate(claim.expectedDate))
            DetailLine(title: "金额", value: FinanceFormatter.money(claim.amount, currency: claim.currency))
            if let actualReceivedDate = claim.actualReceivedDate {
                DetailLine(title: "实际到账", value: FinanceFormatter.mediumDate(actualReceivedDate))
            }
            if let receivedAccountId = claim.receivedAccountId {
                DetailLine(title: "到账账户", value: accounts.first { $0.id == receivedAccountId }?.name ?? "未知账户")
            }
            DetailNote(claim.note)
        }
    }

    private var entryTitle: String {
        entries.first { $0.id == claim.linkedEntryId }?.title ?? "关联记录"
    }
}

private struct CreditCycleDetail: View {
    let cycle: CreditStatementCycleDTO
    let accounts: [AccountDTO]

    var body: some View {
        DetailSection(title: "账单周期", systemImage: "calendar.badge.clock", headline: accountName) {
            StatusTag(status: cycle.status)
            DetailLine(title: "周期", value: "\(FinanceFormatter.mediumDate(cycle.cycleStartDate)) - \(FinanceFormatter.mediumDate(cycle.cycleEndDate))")
            DetailLine(title: "出账日", value: FinanceFormatter.mediumDate(cycle.statementDate))
            DetailLine(title: "还款日", value: FinanceFormatter.mediumDate(cycle.dueDate))
            DetailLine(title: "账单金额", value: FinanceFormatter.money(cycle.statementAmount, currency: cycle.currency))
            DetailLine(title: "已还", value: FinanceFormatter.money(cycle.paidAmount, currency: cycle.currency))
            DetailLine(title: "剩余", value: FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency))
            DetailLine(title: "最低还款", value: FinanceFormatter.money(cycle.minimumPayment, currency: cycle.currency))
            DetailNote(cycle.note)
        }
    }

    private var accountName: String {
        accounts.first { $0.id == cycle.creditAccountId }?.name ?? "信用账户"
    }
}

private struct InstallmentDetail: View {
    let plan: InstallmentPlanDTO
    let accounts: [AccountDTO]
    let entries: [EntryDTO]

    var body: some View {
        DetailSection(title: "分期计划", systemImage: "rectangle.stack.badge.plus", headline: entryTitle) {
            StatusTag(status: plan.status)
            DetailLine(title: "信用账户", value: accounts.first { $0.id == plan.creditAccountId }?.name ?? "未知账户")
            DetailLine(title: "总金额", value: FinanceFormatter.money(plan.totalAmount, currency: plan.currency))
            DetailLine(title: "每期金额", value: FinanceFormatter.money(plan.paymentAmount, currency: plan.currency))
            DetailLine(title: "期数", value: "\(plan.numberOfPayments)")
            DetailLine(title: "开始日期", value: FinanceFormatter.mediumDate(plan.startDate))
            DetailLine(title: "已生成现金流", value: "\(plan.generatedCashFlowCount)")
            DetailNote(plan.note)
        }
    }

    private var entryTitle: String {
        entries.first { $0.id == plan.linkedEntryId }?.title ?? "关联信用消费"
    }
}

private struct SubscriptionDetail: View {
    let rule: SubscriptionRuleDTO
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]

    var body: some View {
        DetailSection(title: "订阅规则", systemImage: "repeat.circle.fill", headline: rule.title) {
            StatusTag(status: rule.status)
            DetailLine(title: "金额", value: FinanceFormatter.money(rule.amount, currency: rule.currency))
            DetailLine(title: "周期", value: rule.billingInterval.financeStatusTitle)
            DetailLine(title: "下次扣款", value: rule.nextChargeDate.map(FinanceFormatter.mediumDate) ?? "未排期")
            DetailLine(title: "账户", value: rule.accountId.flatMap(accountName) ?? "未关联")
            DetailLine(title: "分类", value: rule.categoryId.flatMap(categoryName) ?? "未关联")
            DetailLine(title: "已生成现金流", value: "\(rule.generatedCashFlowCount)")
            DetailNote(rule.note)
        }
    }

    private func accountName(_ id: String) -> String? {
        accounts.first { $0.id == id }?.name
    }

    private func categoryName(_ id: String) -> String? {
        categories.first { $0.id == id }?.name
    }
}

private struct AIPlanDetail: View {
    let plan: AIPlanDTO

    var body: some View {
        DetailSection(title: "AI 计划", systemImage: "sparkles", headline: plan.sourceText) {
            HStack {
                StatusTag(status: plan.status)
                StatusTag(status: plan.riskLevel)
            }
            DetailLine(title: "Provider", value: plan.provider)
            DetailLine(title: "模型", value: plan.model ?? "未返回")
            DetailLine(title: "动作数", value: "\(plan.actions.count)")
            DetailLine(title: "自动确认", value: plan.autoConfirmEligible ? "允许" : "需要人工确认")
            if let confidence = plan.confidence {
                DetailLine(title: "置信度", value: NSDecimalNumber(decimal: confidence.value).stringValue)
            }
            DetailNote(plan.explanation)
            if !plan.actions.isEmpty {
                Divider()
                Text("动作").font(.headline)
                ForEach(plan.actions) { action in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(action.actionType.financeStatusTitle)
                                .font(.headline)
                            Spacer()
                            StatusTag(status: action.status)
                        }
                        if let explanation = action.explanation {
                            Text(explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct NotificationRuleDetail: View {
    let rule: NotificationRuleDTO

    var body: some View {
        DetailSection(title: "通知规则", systemImage: "bell.badge.fill", headline: rule.title) {
            HStack {
                StatusTag(status: rule.status)
                StatusTag(status: rule.ruleType)
                StatusTag(status: rule.channel)
            }
            if let nextTriggerDate = rule.nextTriggerDate {
                DetailLine(title: "下次触发", value: FinanceFormatter.mediumDate(nextTriggerDate))
            }
            if let lastTriggeredAt = rule.lastTriggeredAt {
                DetailLine(title: "上次触发", value: FinanceFormatter.mediumDate(lastTriggeredAt))
            }
            if !rule.triggerPayload.isEmpty {
                Divider()
                Text("触发条件").font(.headline)
                ForEach(rule.triggerPayload.keys.sorted(), id: \.self) { key in
                    DetailLine(title: key, value: rule.triggerPayload[key]?.displayText ?? "")
                }
            }
            DetailNote(rule.note)
        }
    }
}

private struct ModuleDetail: View {
    let module: FinanceModule

    var body: some View {
        DetailSection(title: module.title, systemImage: module.symbolName, headline: module.title) {
            Text(moduleHint)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var moduleHint: String {
        switch module {
        case .dashboard: "总览会汇总账户净值、未来现金流、报销抵扣和 AI 待确认计划。"
        case .accounts: "选择一个账户后，这里会显示余额、信用额度、账单日和还款日。"
        case .entries: "选择一条记录后，这里会显示分类明细、账户流水和报销标记。"
        case .cashFlow: "选择现金流后，可以核对预计日期、关联账户、分类和结算状态。"
        case .reimbursements: "选择报销后，可以查看审批状态、到账账户和关联记录。"
        case .credit: "选择账单、分期或订阅后，这里会显示信用负债细节。"
        case .reports: "分析页提供月度、分类、现金流、信用、报销、订阅和 CSV 导出。"
        case .ai: "AI 计划必须在这里或主面板中完成确认；高风险执行需要强确认。"
        case .notifications: "选择通知规则后，可以查看规则状态、触发条件和下一次触发时间。"
        case .settings: "设置页展示 API 连接、AI 配置状态、默认币种和手动汇率。"
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    let headline: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(headline)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            content
        }
    }
}

private struct DetailNote: View {
    let note: String?

    init(_ note: String?) {
        self.note = note
    }

    var body: some View {
        if let note, !note.isEmpty {
            Divider()
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
