import Foundation

public struct AuditLog: Codable, Equatable, Sendable {
    public let id: String
    public let actor: String
    public let actionType: String
    public let targetType: String
    public let targetID: String
    public let beforeSnapshot: [String: JSONValue]?
    public let afterSnapshot: [String: JSONValue]?
    public let note: String?

    public init(
        id: String,
        actor: String,
        actionType: String,
        targetType: String,
        targetID: String,
        beforeSnapshot: [String: JSONValue]? = nil,
        afterSnapshot: [String: JSONValue]? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.actor = actor
        self.actionType = actionType
        self.targetType = targetType
        self.targetID = targetID
        self.beforeSnapshot = beforeSnapshot
        self.afterSnapshot = afterSnapshot
        self.note = note
    }
}
