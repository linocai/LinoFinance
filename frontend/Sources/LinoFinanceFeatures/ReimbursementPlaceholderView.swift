import LinoFinanceCore
import LinoFinanceDesignSystem
import SwiftUI

public struct ReimbursementPlaceholderView: View {
    private let claimAmount = MoneyAmount(amountMinor: 500_00, currency: .cny)

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reimbursement")
                .font(.headline)
            MoneyText(claimAmount)
            HStack(spacing: 8) {
                StatusTag("submitted", style: .expected)
                StatusTag("future inflow", style: .confirmed)
            }
        }
        .padding()
    }
}

