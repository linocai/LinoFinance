import Foundation

public enum AIRiskLevel: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum AIPlanStatus: String, Codable, Equatable, Sendable {
    case autoConfirmCandidate = "auto_confirm_candidate"
    case requiresConfirmation = "requires_confirmation"
    case approved
    case executed
    case rejected
    case failed
    case cancelled
}

public enum AIActionType: String, Codable, Equatable, Sendable {
    case createEntry = "CreateEntry"
    case createCashFlowItem = "CreateCashFlowItem"
    case markReimbursable = "MarkReimbursable"
    case createInstallmentPlan = "CreateInstallmentPlan"
    case recordCreditRepayment = "RecordCreditRepayment"
    case generateNotificationRule = "GenerateNotificationRule"
    case setCashFlowStatus = "SetCashFlowStatus"
    case updateReimbursementStatus = "UpdateReimbursementStatus"
    case voidEntry = "VoidEntry"
}

public enum AIActionStatus: String, Codable, Equatable, Sendable {
    case pending
    case executed
    case failed
    case rolledBack = "rolled_back"
    case skipped
}

public struct AIAction: Codable, Equatable, Sendable {
    public let id: String
    public let planID: String
    public let executionOrder: Int
    public let actionType: AIActionType
    public let status: AIActionStatus
    public let riskLevel: AIRiskLevel
    public let requiresConfirmation: Bool
    public let payload: [String: JSONValue]
    public let explanation: String?
    public let result: [String: JSONValue]?
    public let rollbackPayload: [String: JSONValue]?
    public let targetType: String?
    public let targetID: String?
    public let errorMessage: String?

    public init(
        id: String,
        planID: String,
        executionOrder: Int,
        actionType: AIActionType,
        status: AIActionStatus,
        riskLevel: AIRiskLevel,
        requiresConfirmation: Bool,
        payload: [String: JSONValue],
        explanation: String? = nil,
        result: [String: JSONValue]? = nil,
        rollbackPayload: [String: JSONValue]? = nil,
        targetType: String? = nil,
        targetID: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.planID = planID
        self.executionOrder = executionOrder
        self.actionType = actionType
        self.status = status
        self.riskLevel = riskLevel
        self.requiresConfirmation = requiresConfirmation
        self.payload = payload
        self.explanation = explanation
        self.result = result
        self.rollbackPayload = rollbackPayload
        self.targetType = targetType
        self.targetID = targetID
        self.errorMessage = errorMessage
    }
}

public struct AIPlan: Codable, Equatable, Sendable {
    public let id: String
    public let sourceText: String
    public let provider: String
    public let model: String?
    public let status: AIPlanStatus
    public let riskLevel: AIRiskLevel
    public let autoConfirmEligible: Bool
    public let confidence: Decimal?
    public let explanation: String?
    public let actions: [AIAction]

    public init(
        id: String,
        sourceText: String,
        provider: String,
        model: String? = nil,
        status: AIPlanStatus,
        riskLevel: AIRiskLevel,
        autoConfirmEligible: Bool,
        confidence: Decimal? = nil,
        explanation: String? = nil,
        actions: [AIAction]
    ) {
        self.id = id
        self.sourceText = sourceText
        self.provider = provider
        self.model = model
        self.status = status
        self.riskLevel = riskLevel
        self.autoConfirmEligible = autoConfirmEligible
        self.confidence = confidence
        self.explanation = explanation
        self.actions = actions
    }
}
