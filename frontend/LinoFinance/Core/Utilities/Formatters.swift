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

    /// Fallback for UTC-naive datetimes that carry microsecond fractional
    /// seconds with no timezone designator (audit §3.5) — e.g. the local SQLite
    /// runner emits `2026-06-10T14:30:00.123456`. The two `ISO8601DateFormatter`
    /// variants require a timezone, and `linoAPIDateTime` has no fractional
    /// seconds, so neither matches. Backend naive datetimes are UTC (§3.2).
    static let linoAPIDateTimeFractional: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()
}

/// Parse a user-entered amount string into a `Decimal`, or `nil` if it is not a
/// clean decimal number.
///
/// Pipeline (v1.3.0, audit 1.4): trim whitespace → strip English thousands
/// separators (`,`) → validate the *whole* string against
/// `^-?[0-9]+(\.[0-9]+)?$` → only then hand off to `Decimal(string:)`.
///
/// We deliberately do **not** strip currency symbols or units: `"58元"`,
/// `"¥100"`, `"1.2.3"`, `""` all return `nil` so the form surfaces an error
/// rather than silently swallowing characters (e.g. `Decimal(string: "58元")`
/// returns `58`). The whole-string regex (rather than a round-trip
/// format-compare) avoids trailing-zero false negatives like `"1.50"` → `"1.5"`.
func parseDecimalAmount(_ raw: String) -> Decimal? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let stripped = trimmed.replacingOccurrences(of: ",", with: "")
    guard stripped.range(
        of: "^-?[0-9]+(\\.[0-9]+)?$",
        options: .regularExpression
    ) != nil else {
        return nil
    }
    return Decimal(string: stripped)
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
