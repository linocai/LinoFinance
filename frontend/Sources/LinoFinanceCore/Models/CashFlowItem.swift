import Foundation

public enum CashFlowDirection: String, Codable, Equatable, Sendable {
    case inflow
    case outflow
    case transfer
}

public enum CashFlowStatus: String, Codable, Equatable, Sendable {
    case expected
    case confirmed
    case settled
    case cancelled
    case partial
}

public enum CashFlowType: String, Codable, Equatable, Sendable {
    case salary
    case rentIncome = "rent_income"
    case reimbursement
    case subscription
    case creditRepayment = "credit_repayment"
    case installment
    case oneTime = "one_time"
    case other
}

public struct CashFlowItem: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let direction: CashFlowDirection
    public let cashFlowType: CashFlowType
    public let amount: MoneyAmount
    public let expectedDate: Date
    public let accountID: String?
    public let categoryID: String?
    public let recurrenceRule: String?
    public let status: CashFlowStatus
    public let linkedEntryID: String?

    public init(
        id: String,
        title: String,
        direction: CashFlowDirection,
        cashFlowType: CashFlowType,
        amount: MoneyAmount,
        expectedDate: Date,
        accountID: String? = nil,
        categoryID: String? = nil,
        recurrenceRule: String? = nil,
        status: CashFlowStatus,
        linkedEntryID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.direction = direction
        self.cashFlowType = cashFlowType
        self.amount = amount
        self.expectedDate = expectedDate
        self.accountID = accountID
        self.categoryID = categoryID
        self.recurrenceRule = recurrenceRule
        self.status = status
        self.linkedEntryID = linkedEntryID
    }
}

