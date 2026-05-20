import Foundation

public enum IntentRecordStatus: String, Equatable, Sendable {
    case draft
    case confirmed
}

public struct IntentRecordResolution: Equatable, Sendable {
    public let status: IntentRecordStatus
    public let accountID: String?
    public let categoryID: String?
    public let missingFields: [String]

    public init(
        status: IntentRecordStatus,
        accountID: String?,
        categoryID: String?,
        missingFields: [String]
    ) {
        self.status = status
        self.accountID = accountID
        self.categoryID = categoryID
        self.missingFields = missingFields
    }
}

public struct IntentNamedCandidate: Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum IntentRecordResolver {
    public static func resolve(
        accountName: String?,
        categoryName: String?,
        accounts: [IntentNamedCandidate],
        categories: [IntentNamedCandidate]
    ) -> IntentRecordResolution {
        let account = match(accountName, in: accounts)
        let category = match(categoryName, in: categories)
        var missing: [String] = []
        if account == nil { missing.append("account") }
        if category == nil { missing.append("category") }
        return IntentRecordResolution(
            status: missing.isEmpty ? .confirmed : .draft,
            accountID: account?.id,
            categoryID: category?.id,
            missingFields: missing
        )
    }

    public static func match(
        _ query: String?,
        in candidates: [IntentNamedCandidate]
    ) -> IntentNamedCandidate? {
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let key = normalized(query)
        return candidates.first { normalized($0.name) == key }
            ?? candidates.first { normalized($0.name).contains(key) || key.contains(normalized($0.name)) }
    }

    public static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct MonthDateWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
}

public enum MonthWindowResolver {
    public static func window(
        month: Int?,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> MonthDateWindow? {
        var calendar = calendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let year = components.year else { return nil }
        let resolvedMonth = month ?? components.month ?? 1
        guard (1...12).contains(resolvedMonth),
              let start = calendar.date(from: DateComponents(year: year, month: resolvedMonth, day: 1)),
              let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else {
            return nil
        }
        return MonthDateWindow(start: start, end: end)
    }
}

public struct SpotlightTargetID: Equatable, Sendable {
    public let type: String
    public let id: String

    public init(type: String, id: String) {
        self.type = type
        self.id = id
    }

    public var uniqueIdentifier: String {
        "linofinance.\(type).\(id)"
    }

    public static func parse(_ uniqueIdentifier: String) -> SpotlightTargetID? {
        let parts = uniqueIdentifier.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "linofinance", !parts[1].isEmpty, !parts[2].isEmpty else {
            return nil
        }
        return SpotlightTargetID(type: parts[1], id: parts[2])
    }
}
