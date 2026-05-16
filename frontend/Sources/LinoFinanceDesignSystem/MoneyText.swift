import LinoFinanceCore
import SwiftUI

public struct MoneyText: View {
    public let money: MoneyAmount
    public let showConvertedAmount: Bool

    public init(_ money: MoneyAmount, showConvertedAmount: Bool = true) {
        self.money = money
        self.showConvertedAmount = showConvertedAmount
    }

    public var body: some View {
        Text(displayText)
            .font(.body.monospacedDigit())
    }

    private var displayText: String {
        guard showConvertedAmount, let converted = money.formattedConvertedCNY else {
            return money.formattedOriginal
        }
        return "\(money.formattedOriginal) · \(converted)"
    }
}

