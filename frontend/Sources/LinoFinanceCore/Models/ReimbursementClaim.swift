import Foundation

public enum ReimbursementStatus: String, Codable, Equatable, Sendable {
    case reimbursable
    case invoicePending = "invoice_pending"
    case submitted
    case approved
    case waitingReceived = "waiting_received"
    case received
    case partialReceived = "partial_received"
    case rejected
    case abandoned
}

public struct ReimbursementClaim: Codable, Equatable, Sendable {
    public let id: String
    public let linkedEntryID: String
    public let linkedEntryLineID: String?
    public let amount: MoneyAmount
    public let payer: String
    public let expectedDate: Date
    public let actualReceivedDate: Date?
    public let receivedAccountID: String?
    public let receivedEntryID: String?
    public let status: ReimbursementStatus
    public let cashFlowItemID: String?

    public init(
        id: String,
        linkedEntryID: String,
        linkedEntryLineID: String? = nil,
        amount: MoneyAmount,
        payer: String,
        expectedDate: Date,
        actualReceivedDate: Date? = nil,
        receivedAccountID: String? = nil,
        receivedEntryID: String? = nil,
        status: ReimbursementStatus,
        cashFlowItemID: String? = nil
    ) {
        self.id = id
        self.linkedEntryID = linkedEntryID
        self.linkedEntryLineID = linkedEntryLineID
        self.amount = amount
        self.payer = payer
        self.expectedDate = expectedDate
        self.actualReceivedDate = actualReceivedDate
        self.receivedAccountID = receivedAccountID
        self.receivedEntryID = receivedEntryID
        self.status = status
        self.cashFlowItemID = cashFlowItemID
    }
}

