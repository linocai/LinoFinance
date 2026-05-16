import LinoFinanceCore
import LinoFinanceDesignSystem
import SwiftUI

public struct ReportsPlaceholderView: View {
    private let monthlyNet = MoneyAmount(amountMinor: 3200_00, currency: .cny)

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reports")
                .font(.headline)
            MoneyText(monthlyNet)
            HStack(spacing: 8) {
                StatusTag("monthly", style: .confirmed)
                StatusTag("csv", style: .expected)
            }
        }
        .padding()
    }
}
