import LinoFinanceCore
import SwiftUI

public struct CurrencyBadge: View {
    public let currency: CurrencyCode

    public init(_ currency: CurrencyCode) {
        self.currency = currency
    }

    public var body: some View {
        Text(currency.rawValue)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
            )
    }
}

