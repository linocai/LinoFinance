import SwiftUI

enum FinanceColor {
    static let brand = Color(red: 0.12, green: 0.44, blue: 0.85)
    static let cny = Color(red: 0.78, green: 0.06, blue: 0.18)
    static let usd = Color(red: 0.18, green: 0.52, blue: 0.35)
    static let income = Color(red: 0.14, green: 0.55, blue: 0.32)
    static let expense = Color(red: 0.78, green: 0.06, blue: 0.18)
    static let credit = Color.orange
    static let pending = Color.secondary
    static let warning = Color.yellow
    static let ai = Color.purple
}

enum FinanceSpacing {
    static var page: CGFloat {
#if os(iOS)
        16
#else
        24
#endif
    }

    static var panel: CGFloat {
#if os(iOS)
        14
#else
        16
#endif
    }

    static let row: CGFloat = 10

    static var cornerRadius: CGFloat {
#if os(iOS)
        14
#else
        16
#endif
    }
}
