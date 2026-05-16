import LinoFinanceCore
import LinoFinanceDesignSystem
import SwiftUI

public struct InstallmentPlaceholderView: View {
    private let monthlyPayment = MoneyAmount(
        amountMinor: 250_00,
        currency: .usd,
        convertedCNYMinor: 1700_00,
        exchangeRate: FinanceDefaults.initialUSDCNYRate
    )

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installment Plan")
                .font(.headline)
            MoneyText(monthlyPayment)
            HStack(spacing: 8) {
                StatusTag("active", style: .expected)
                StatusTag("cash flow", style: .confirmed)
            }
        }
        .padding()
    }
}
