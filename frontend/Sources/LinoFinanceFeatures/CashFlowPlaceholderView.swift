import LinoFinanceCore
import LinoFinanceDesignSystem
import SwiftUI

public struct CashFlowPlaceholderView: View {
    private let upcomingPayment = MoneyAmount(
        amountMinor: 200_00,
        currency: .usd,
        convertedCNYMinor: 1360_00,
        exchangeRate: FinanceDefaults.initialUSDCNYRate
    )

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Cash Flow")
                .font(.headline)
            MoneyText(upcomingPayment)
            HStack(spacing: 8) {
                StatusTag("expected", style: .expected)
                StatusTag("not ledgered", style: .draft)
            }
        }
        .padding()
    }
}

