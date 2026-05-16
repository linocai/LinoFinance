import Foundation

public enum CreditStatementStatus: String, Codable, Equatable, Sendable {
    case open
    case statementGenerated = "statement_generated"
    case partiallyPaid = "partially_paid"
    case paid
    case overdue
    case closed
}

public struct CreditStatementCycle: Codable, Equatable, Sendable {
    public let id: String
    public let creditAccountID: String
    public let cycleStartDate: Date
    public let cycleEndDate: Date
    public let statementDate: Date
    public let dueDate: Date
    public let currency: CurrencyCode
    public let statementAmountMinor: Int64
    public let minimumPaymentMinor: Int64
    public let paidAmountMinor: Int64
    public let remainingAmountMinor: Int64
    public let status: CreditStatementStatus

    public init(
        id: String,
        creditAccountID: String,
        cycleStartDate: Date,
        cycleEndDate: Date,
        statementDate: Date,
        dueDate: Date,
        currency: CurrencyCode,
        statementAmountMinor: Int64,
        minimumPaymentMinor: Int64,
        paidAmountMinor: Int64,
        remainingAmountMinor: Int64,
        status: CreditStatementStatus
    ) {
        self.id = id
        self.creditAccountID = creditAccountID
        self.cycleStartDate = cycleStartDate
        self.cycleEndDate = cycleEndDate
        self.statementDate = statementDate
        self.dueDate = dueDate
        self.currency = currency
        self.statementAmountMinor = statementAmountMinor
        self.minimumPaymentMinor = minimumPaymentMinor
        self.paidAmountMinor = paidAmountMinor
        self.remainingAmountMinor = remainingAmountMinor
        self.status = status
    }
}

