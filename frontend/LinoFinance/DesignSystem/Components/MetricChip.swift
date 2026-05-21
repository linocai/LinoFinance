import SwiftUI

/// 小号 key-value tile —— 对齐 HTML `.row-stats .stat` 和 hero 下方的 mini metric。
/// `tint` 默认走 brand；数值走 tabular numerals。
struct MetricChip: View {
    let title: String
    let value: String
    var tint: Color = FinanceTokens.Brand.primary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(FinanceTypography.pillLabel)
                .foregroundStyle(FinanceTokens.Text.secondary)
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .glassBackground(radius: FinanceTokens.Radius.md, strength: .regular, elevation: nil)
    }
}
