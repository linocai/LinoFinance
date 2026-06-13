import SwiftUI

// AmountText — a single monospaced-digit money figure (HANDOFF §2.4 + §6).
//
// Binds the shared Core `DecimalValue` + `CurrencyCode`. Always uses
// `.monospacedDigit()`, an explicit ASCII sign (`+` / `-`, never the unicode
// minus), and groups thousands. Color is decided by the caller (income green /
// expense red / neutral) — this view does not impose semantic color.

struct AmountText: View {
    let value: DecimalValue
    var currency: CurrencyCode = .cny
    /// Show a leading `+` for positive values (e.g. P&L deltas). Negatives always
    /// get a leading ASCII `-`.
    var showsPositiveSign: Bool = false
    /// Whether to prefix the currency symbol (¥ / $).
    var showsSymbol: Bool = true
    var font: Font = Theme.Font.cardNumber()
    var color: Color = Theme.Color.textPrimary

    var body: some View {
        Text(formatted)
            .font(font)
            .monospacedDigit()
            // A money figure must never wrap. In tight columns shrink to fit
            // rather than breaking onto a second line (hero dual-currency, etc.).
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(color)
    }

    private var formatted: String {
        let decimal = value.value
        let isNegative = decimal < 0
        let magnitude = isNegative ? -decimal : decimal
        let number = Self.grouping.string(from: NSDecimalNumber(decimal: magnitude))
            ?? "\(magnitude)"
        let symbol = showsSymbol ? currency.symbol : ""
        let sign: String
        if isNegative {
            sign = "-"               // ASCII hyphen-minus, never U+2212
        } else if showsPositiveSign {
            sign = "+"
        } else {
            sign = ""
        }
        return "\(sign)\(symbol)\(number)"
    }

    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
