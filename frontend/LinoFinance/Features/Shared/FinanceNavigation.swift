import Foundation

enum FinanceModule: String, CaseIterable, Identifiable {
    case dashboard
    case accounts
    case entries
    case cashFlow
    case reimbursements
    case credit
    case reports
    case ai
    case notifications
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "总览"
        case .accounts: "账户"
        case .entries: "记账"
        case .cashFlow: "现金流"
        case .reimbursements: "报销"
        case .credit: "信用"
        case .reports: "分析"
        case .ai: "AI"
        case .notifications: "通知"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "chart.pie.fill"
        case .accounts: "wallet.pass.fill"
        case .entries: "square.and.pencil"
        case .cashFlow: "arrow.left.arrow.right.circle.fill"
        case .reimbursements: "arrow.uturn.left.circle.fill"
        case .credit: "creditcard.trianglebadge.exclamationmark"
        case .reports: "chart.line.uptrend.xyaxis"
        case .ai: "sparkles"
        case .notifications: "bell.badge.fill"
        case .settings: "gearshape.fill"
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
