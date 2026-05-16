import Foundation

public enum NotificationRuleType: String, Codable, Equatable, Sendable {
    case creditRepayment = "credit_repayment"
    case cashFlow = "cash_flow"
    case reimbursement
    case subscription
    case anomaly
}

public enum NotificationChannel: String, Codable, Equatable, Sendable {
    case inApp = "in_app"
    case system
    case email
}

public enum NotificationRuleStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case cancelled
}

public struct NotificationRule: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let ruleType: NotificationRuleType
    public let channel: NotificationChannel
    public let triggerPayload: [String: JSONValue]
    public let status: NotificationRuleStatus
    public let nextTriggerDate: Date?
    public let note: String?

    public init(
        id: String,
        title: String,
        ruleType: NotificationRuleType,
        channel: NotificationChannel,
        triggerPayload: [String: JSONValue],
        status: NotificationRuleStatus,
        nextTriggerDate: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.ruleType = ruleType
        self.channel = channel
        self.triggerPayload = triggerPayload
        self.status = status
        self.nextTriggerDate = nextTriggerDate
        self.note = note
    }
}
