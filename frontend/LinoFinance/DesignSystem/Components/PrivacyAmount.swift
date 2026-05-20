import SwiftUI

struct PrivacyAmount: View {
    let value: String
    var font: Font = FinanceTypography.bodyMono
    var tint: Color = FinanceTokens.Text.primary
    var alignment: TextAlignment = .leading

    @AppStorage("linofinance.privacyMaskEnabled") private var privacyMaskEnabled = false

    var body: some View {
        Text(privacyMaskEnabled ? maskedValue : value)
            .font(font)
            .foregroundStyle(tint)
            .multilineTextAlignment(alignment)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var maskedValue: String {
        let visibleCurrency = value.prefix { !$0.isNumber && $0 != "." && $0 != "," && $0 != "-" }
        let prefix = visibleCurrency.isEmpty ? "" : "\(visibleCurrency)"
        return "\(prefix)****"
    }
}
