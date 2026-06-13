import SwiftUI

// CurrencyAmountView — CNY / USD side by side, equal size, distinct color (§5).
//
// The client's hard requirement: CNY and USD are ALWAYS shown together, side by
// side, equally prominent. `*_by_currency` API fields are original-currency (not
// converted), so each leg carries its own `DecimalValue`. Either leg may be
// absent (some accounts hold only one currency) — pass `nil` to hide it.

struct CurrencyAmountView: View {
    var cny: DecimalValue?
    var usd: DecimalValue?
    /// Stack horizontally (default) or vertically (tight cards).
    var axis: Axis = .horizontal
    var font: Font = Theme.Font.cardNumber()
    /// Show explicit `+` on positives (P&L style).
    var showsPositiveSign: Bool = false

    var body: some View {
        let cnyView = cny.map { leg($0, currency: .cny, color: Theme.Color.cny) }
        let usdView = usd.map { leg($0, currency: .usd, color: Theme.Color.usd) }

        Group {
            switch axis {
            case .horizontal:
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    cnyView
                    if cny != nil && usd != nil { separator }
                    usdView
                }
            case .vertical:
                VStack(alignment: .leading, spacing: 4) {
                    cnyView
                    usdView
                }
            }
        }
    }

    private func leg(_ value: DecimalValue, currency: CurrencyCode, color: Color) -> some View {
        AmountText(
            value: value,
            currency: currency,
            showsPositiveSign: showsPositiveSign,
            font: font,
            color: color
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Color.divider)
            .frame(width: 1, height: 20)
    }
}
