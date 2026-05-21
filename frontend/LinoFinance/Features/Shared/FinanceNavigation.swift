import Foundation

enum FinanceModule: String, CaseIterable, Identifiable, Hashable, Codable {
    case dashboard
    case accounts
    case entries
    case cashFlow
    case reimbursements
    case credit
    case reports
    case ai
    case aiMemo
    case reconciliation
    case notifications
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "总览"
        case .accounts: "账户"
        case .entries: "记账"
        case .cashFlow: "现金流"
        case .reimbursements: "报销中心"
        case .credit: "信用 · 账单"
        case .reports: "报表"
        case .ai: "AI 工作台"
        case .aiMemo: "AI 月报"
        case .reconciliation: "对账"
        case .notifications: "通知规则"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .accounts: "wallet.bifold"
        case .entries: "square.and.pencil"
        case .cashFlow: "arrow.left.arrow.right"
        case .reimbursements: "arrow.uturn.left"
        case .credit: "creditcard"
        case .reports: "chart.bar"
        case .ai: "sparkles"
        case .aiMemo: "doc.text.magnifyingglass"
        case .reconciliation: "checklist"
        case .notifications: "bell"
        case .settings: "gearshape"
        }
    }
}

enum InspectorSelection: Identifiable, Equatable {
    case account(AccountDTO)
    case entry(EntryDTO)
    case cashFlow(CashFlowItemDTO)
    case reimbursement(ReimbursementClaimDTO)
    case creditCycle(CreditStatementCycleDTO)
    case installment(InstallmentPlanDTO)
    case subscription(SubscriptionRuleDTO)
    case aiPlan(AIPlanDTO)
    case notification(NotificationRuleDTO)
    case module(FinanceModule)

    var id: String {
        switch self {
        case .account(let account): "account-\(account.id)"
        case .entry(let entry): "entry-\(entry.id)"
        case .cashFlow(let item): "cashflow-\(item.id)"
        case .reimbursement(let claim): "reimbursement-\(claim.id)"
        case .creditCycle(let cycle): "cycle-\(cycle.id)"
        case .installment(let plan): "installment-\(plan.id)"
        case .subscription(let rule): "subscription-\(rule.id)"
        case .aiPlan(let plan): "ai-\(plan.id)"
        case .notification(let rule): "notification-\(rule.id)"
        case .module(let module): "module-\(module.id)"
        }
    }
}
