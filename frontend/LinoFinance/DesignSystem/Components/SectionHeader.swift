import SwiftUI

/// 大块章节头 —— 对齐 HTML `.section-head`（eyebrow + h2 + description + trailing 段控件）。
struct SectionHeader<Trailing: View>: View {
    let kicker: String?
    let title: String
    let description: String?
    @ViewBuilder var trailing: Trailing

    init(
        kicker: String? = nil,
        title: String,
        description: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.kicker = kicker
        self.title = title
        self.description = description
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if let kicker {
                    Text(kicker.uppercased())
                        .font(FinanceTypography.sectionKicker)
                        .kickerTracking()
                        .foregroundStyle(FinanceTokens.Brand.primary)
                }
                Text(title)
                    .font(FinanceTypography.titleXL)
                    .titleTracking()
                    .foregroundStyle(FinanceTokens.Text.primary)
                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}
