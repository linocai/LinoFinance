import Foundation

public enum InstallmentPlanStatus: String, Codable, Equatable, Sendable {
    case active
    case paidOff = "paid_off"
    case earlyPaidOff = "early_paid_off"
    case cancelled
}

public struct InstallmentPlan: Codable, Equatable, Sendable {
    public let id: String
    public let linkedEntryID: String
    public let creditAccountID: String
    public let totalAmount: MoneyAmount
    public let numberOfPayments: Int
    public let paymentAmount: MoneyAmount
    public let feeAmount: MoneyAmount
    public let interestAmount: MoneyAmount
    public let startDate: Date
    public let endDate: Date
    public let status: InstallmentPlanStatus
    public let generatedCashFlowCount: Int
    public let note: String?

    public init(
        id: String,
        linkedEntryID: String,
        creditAccountID: String,
        totalAmount: MoneyAmount,
        numberOfPayments: Int,
        paymentAmount: MoneyAmount,
        feeAmount: MoneyAmount,
        interestAmount: MoneyAmount,
        startDate: Date,
        endDate: Date,
        status: InstallmentPlanStatus,
        generatedCashFlowCount: Int,
        note: String? = nil
    ) {
        self.id = id
        self.linkedEntryID = linkedEntryID
        self.creditAccountID = creditAccountID
        self.totalAmount = totalAmount
        self.numberOfPayments = numberOfPayments
        self.paymentAmount = paymentAmount
        self.feeAmount = feeAmount
        self.interestAmount = interestAmount
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.generatedCashFlowCount = generatedCashFlowCount
        self.note = note
    }
}
