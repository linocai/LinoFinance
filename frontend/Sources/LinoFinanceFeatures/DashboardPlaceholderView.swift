import LinoFinanceCore
import LinoFinanceDesignSystem
import SwiftUI

public struct DashboardPlaceholderView: View {
    private let sampleNetWorth = MoneyAmount(
        amountMinor: 510_000,
        currency: .usd,
        convertedCNYMinor: 3_468_000,
        exchangeRate: FinanceDefaults.initialUSDCNYRate
    )

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Net Worth")
                .font(.headline)
            MoneyText(sampleNetWorth)
                .font(.title2)
            HStack(spacing: 8) {
                StatusTag("drafts excluded", style: .draft)
                CurrencyBadge(.usd)
                CurrencyBadge(.cny)
            }
        }
        .padding()
    }
}

