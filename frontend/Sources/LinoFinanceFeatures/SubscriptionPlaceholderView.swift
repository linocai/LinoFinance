import LinoFinanceCore
import LinoFinanceDesignSystem
import SwiftUI

public struct SubscriptionPlaceholderView: View {
    private let nextCharge = MoneyAmount(amountMinor: 88_00, currency: .cny)

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription")
                .font(.headline)
            MoneyText(nextCharge)
            HStack(spacing: 8) {
                StatusTag("monthly", style: .expected)
                StatusTag("next charge", style: .warning)
            }
        }
        .padding()
    }
}
