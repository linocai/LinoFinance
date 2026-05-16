import LinoFinanceCore
import LinoFinanceDesignSystem
import SwiftUI

public struct CreditStatementPlaceholderView: View {
    private let statementBalance = MoneyAmount(
        amountMinor: 120_000,
        currency: .usd,
        convertedCNYMinor: 816_000,
        exchangeRate: FinanceDefaults.initialUSDCNYRate
    )

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Credit Statement")
                .font(.headline)
            MoneyText(statementBalance)
            HStack(spacing: 8) {
                StatusTag("statement cycle", style: .expected)
                StatusTag("repayment is transfer", style: .confirmed)
            }
        }
        .padding()
    }
}

