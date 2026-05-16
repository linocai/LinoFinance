import Foundation

public enum SubscriptionBillingInterval: String, Codable, Equatable, Sendable {
    case weekly
    case monthly
    case yearly
}

public enum SubscriptionRuleStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case cancelled
}

public struct SubscriptionRule: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let amount: MoneyAmount
    public let accountID: String?
    public let categoryID: String?
    public let billingInterval: SubscriptionBillingInterval
    public let billingDay: Int?
    public let startDate: Date
    public let endDate: Date?
    public let nextChargeDate: Date
    public let status: SubscriptionRuleStatus
    public let generatedCashFlowCount: Int
    public let note: String?

    public init(
        id: String,
        title: String,
        amount: MoneyAmount,
        accountID: String? = nil,
        categoryID: String? = nil,
        billingInterval: SubscriptionBillingInterval,
        billingDay: Int? = nil,
        startDate: Date,
        endDate: Date? = nil,
        nextChargeDate: Date,
        status: SubscriptionRuleStatus,
        generatedCashFlowCount: Int,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.accountID = accountID
        self.categoryID = categoryID
        self.billingInterval = billingInterval
        self.billingDay = billingDay
        self.startDate = startDate
        self.endDate = endDate
        self.nextChargeDate = nextChargeDate
        self.status = status
        self.generatedCashFlowCount = generatedCashFlowCount
        self.note = note
    }
}
