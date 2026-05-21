import Foundation

/// 跨平台 —— iOS QuickEntrySheet + macOS MacQuickEntryView 共用的 intent 与 error 类型。
enum QuickEntryIntent: String, CaseIterable, Identifiable {
    case expense
    case income
    case creditCharge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .creditCharge: "信用消费"
        }
    }

    var categoryDirection: CategoryDirection {
        switch self {
        case .income: .income
        case .expense, .creditCharge: .expense
        }
    }

    var movementType: MovementType {
        switch self {
        case .income: .balanceIn
        case .expense: .balanceOut
        case .creditCharge: .creditCharge
        }
    }
}

enum QuickEntryError: LocalizedError {
    case emptyText
    case missingTitle
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .emptyText: "请输入或粘贴一段文本。"
        case .missingTitle: "请输入标题。"
        case .invalidAmount: "请输入有效金额。"
        }
    }
}
