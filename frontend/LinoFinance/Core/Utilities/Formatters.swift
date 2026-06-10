import Foundation

extension DateFormatter {
    static let linoAPIDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // 纯日历日(yyyy-MM-dd)必须按本地时区格式化:日期选择器给的是本地零点的
        // Date,若按 UTC 格式化会在 UTC+8 退回前一天(选 6/2 存成 6/1)。
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let linoAPIDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}

enum FinanceFormatter {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    static func money(_ value: DecimalValue, currency: CurrencyCode = .cny, approximate: Bool = false) -> String {
        let formatter = currencyFormatter
        formatter.currencySymbol = currency.symbol
        let text = formatter.string(from: NSDecimalNumber(decimal: value.value)) ?? "\(currency.symbol)\(value.value)"
        return approximate ? "约 \(text)" : text
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }

    static func mediumDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    static func signedMoney(_ value: DecimalValue, currency: CurrencyCode = .cny) -> String {
        if value.value < 0 {
            return "−\(money(DecimalValue(absDecimal(value.value)), currency: currency))"
        }
        return money(value, currency: currency)
    }

    private static func absDecimal(_ value: Decimal) -> Decimal {
        value < 0 ? value * Decimal(-1) : value
    }
}
