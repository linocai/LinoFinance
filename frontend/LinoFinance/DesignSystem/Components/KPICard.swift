import SwiftUI

/// KPI 卡 —— 对齐 HTML `.kpi`（macOS Dashboard 4-col 网格）。
/// 内部布局自上而下：
///   1. 顶部 row: AccountIconTile（左） + StatusTag（右，可选）
///   2. 中部: 大号 mono 数字（38pt semibold tabular），整数高对比 + 小数低对比
///   3. 底部 label（13pt secondary）+ trend（12pt 语义色，可选）
struct KPICard: View {
    let title: String
    private let values: [String]
    let systemImage: String
    var tint: Color = FinanceTokens.Brand.primary
    var tag: TagSpec? = nil
    var trend: TrendSpec? = nil

    struct TagSpec {
        let text: String
        let style: StatusTag.Style
    }

    struct TrendSpec {
        let text: String
        let tint: Color
    }

    init(
        title: String,
        value: String,
        systemImage: String,
        tint: Color = FinanceTokens.Brand.primary,
        tag: TagSpec? = nil,
        trend: TrendSpec? = nil
    ) {
        self.title = title
        self.values = [value]
        self.systemImage = systemImage
        self.tint = tint
        self.tag = tag
        self.trend = trend
    }

    /// Multi-currency variant — renders up to 2 stacked lines (CNY + USD).
    /// Anything beyond the first 2 lines is dropped.
    init(
        title: String,
        valueLines: [String],
        systemImage: String,
        tint: Color = FinanceTokens.Brand.primary,
        tag: TagSpec? = nil,
        trend: TrendSpec? = nil
    ) {
        self.title = title
        let trimmed = Array(valueLines.prefix(2))
        self.values = trimmed.isEmpty ? ["—"] : trimmed
        self.systemImage = systemImage
        self.tint = tint
        self.tag = tag
        self.trend = trend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                AccountIconTile(systemImage: systemImage, tint: tint, size: 32, radius: 10)
                Spacer()
                if let tag {
                    StatusTag(title: tag.text, style: tag.style)
                }
            }

            if values.count == 1 {
                PrivacyAmount(
                    value: values[0],
                    font: FinanceTypography.statValue,
                    tint: FinanceTokens.Text.primary
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        PrivacyAmount(
                            value: value,
                            font: .system(size: 22, weight: .semibold).monospacedDigit(),
                            tint: FinanceTokens.Text.primary
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(FinanceTokens.Text.secondary)
                if let trend {
                    Text(trend.text)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(trend.tint)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(
            radius: FinanceTokens.Radius.lg,
            strength: .strong,
            accent: AnyShapeStyle(FinanceTokens.Halo.brandCorner),
            elevation: .soft
        )
    }
}
