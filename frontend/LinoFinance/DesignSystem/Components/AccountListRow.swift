import SwiftUI

/// 三列行模板 —— 对齐 HTML `.list-row`：icon-tile 左 + (title + sub) 中 + amount 右。
/// Dashboard 账户全景、Today's Entries、Accounts 页、Entries 页都用这个。
struct AccountListRow<Trailing: View>: View {
    let systemImage: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let amountPrimary: String
    var amountSecondary: String? = nil
    var amountTint: Color = FinanceTokens.Text.primary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AccountIconTile(systemImage: systemImage, tint: iconTint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FinanceTokens.Text.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(FinanceTypography.caption)
                    .foregroundStyle(FinanceTokens.Text.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                PrivacyAmount(
                    value: amountPrimary,
                    font: .system(size: 14, weight: .semibold).monospacedDigit(),
                    tint: amountTint,
                    alignment: .trailing
                )
                if let amountSecondary {
                    Text(amountSecondary)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(FinanceTokens.Text.tertiary)
                }
            }

            trailing()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

extension AccountListRow where Trailing == EmptyView {
    init(
        systemImage: String,
        iconTint: Color,
        title: String,
        subtitle: String,
        amountPrimary: String,
        amountSecondary: String? = nil,
        amountTint: Color = FinanceTokens.Text.primary
    ) {
        self.init(
            systemImage: systemImage,
            iconTint: iconTint,
            title: title,
            subtitle: subtitle,
            amountPrimary: amountPrimary,
            amountSecondary: amountSecondary,
            amountTint: amountTint,
            trailing: { EmptyView() }
        )
    }
}
