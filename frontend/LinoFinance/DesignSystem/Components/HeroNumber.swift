import SwiftUI

struct HeroNumber: View {
    let value: String
    var tint: Color = FinanceTokens.Text.primary
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(value)
            .font(FinanceTypography.heroNumber)
            .foregroundStyle(tint)
            .multilineTextAlignment(alignment)
            .lineLimit(2)
            .minimumScaleFactor(0.62)
            .fixedSize(horizontal: false, vertical: true)
    }
}
