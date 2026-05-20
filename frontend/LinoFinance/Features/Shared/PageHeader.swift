import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
#if os(iOS)
                .font(FinanceTypography.headline)
#else
                .font(FinanceTypography.titleXL)
#endif
                .foregroundStyle(FinanceTokens.Text.primary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
