#if os(macOS)
import SwiftUI

/// 总览页全宽横幅卡 —— v1.4.0 P3 引入，取代旧的四宫格 `KPICard`。
///
/// 三段式横向布局：
///   • 左：图标 tile + 标题 + tag（固定宽度，纵向堆叠）
///   • 中：大数字区（双币等大异色），由调用方注入
///   • 右：辅助区（trend 行 / 今日盈亏快录表单等），由调用方注入
///
/// 设计沿用现有 Liquid Glass 风格：`glassBackground(strength: .strong)` +
/// 右上 brand 角落光晕，与 AccountPanoramaCard / 旧 KPICard 一致的圆角、阴影、材质。
struct OverviewBannerCard<Center: View, Trailing: View>: View {
    let title: String
    let systemImage: String
    /// 卡片主 tint —— icon tile 底色 + CNY 数字色。
    let tint: Color
    var tag: TagSpec?
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    struct TagSpec {
        let text: String
        let style: StatusTag.Style
    }

    var body: some View {
        // 响应式：宽屏单行三段；宽度不足时辅助区（今日盈亏表单 / 净资产公式）
        // 整块落到数字下方，避免横向挤压/重叠（如开「详情」检查器压窄主内容时）。
        ViewThatFits(in: .horizontal) {
            rowLayout
            stackedLayout
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(
            radius: FinanceTokens.Radius.lg,
            strength: .strong,
            accent: AnyShapeStyle(FinanceTokens.Halo.brandCorner),
            elevation: .soft
        )
    }

    // 宽屏：左（icon+标题）| 中（双币数字）| 右（辅助区）单行横排。
    private var rowLayout: some View {
        HStack(alignment: .center, spacing: 24) {
            leading
                .frame(width: 188, alignment: .leading)
            center
            Spacer(minLength: 24)
            trailing
        }
    }

    // 窄屏：左+数字一行，辅助区整块落到下方铺满。
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 24) {
                leading
                    .frame(width: 188, alignment: .leading)
                center
                Spacer(minLength: 0)
            }
            trailing
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var leading: some View {
        VStack(alignment: .leading, spacing: 12) {
            AccountIconTile(systemImage: systemImage, tint: tint, size: 40, radius: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(FinanceTypography.headline)
                    .foregroundStyle(FinanceTokens.Text.primary)
                if let tag {
                    StatusTag(title: tag.text, style: tag.style)
                }
            }
        }
    }
}

/// 双币等大数字行 —— P3 核心视觉：CNY / USD 同字号（`statValue`），异色。
/// CNY 用卡片主 tint（各卡 identity 色），USD（及其它非 CNY）用中性次色
/// `FinanceTokens.Text.secondary` —— 主次分明且永不与任一卡主色撞色。
/// 缺某币种时只渲染存在的那一行（`_pack_with_cny_floor` 语义：USD 为 0 时不返回）。
struct DualCurrencyValue: View {
    /// 已格式化的币种数字行（含币种符号），顺序按后端返回（CNY 在前）。
    let lines: [CurrencyLine]
    /// CNY 行的颜色（卡片主 tint）。
    let cnyTint: Color

    struct CurrencyLine: Identifiable {
        let id = UUID()
        let currency: CurrencyCode
        let text: String
        /// 覆盖默认配色（如卡4 按正负 income/expense 着色）。nil 走默认双色规则。
        var overrideTint: Color?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if lines.isEmpty {
                PrivacyAmount(
                    value: "—",
                    font: FinanceTypography.statValue,
                    tint: FinanceTokens.Text.tertiary
                )
            } else {
                ForEach(lines) { line in
                    PrivacyAmount(
                        value: line.text,
                        font: FinanceTypography.statValue,
                        tint: tint(for: line)
                    )
                }
            }
        }
    }

    private func tint(for line: CurrencyLine) -> Color {
        if let override = line.overrideTint { return override }
        // CNY → 卡片主 tint；USD（及其它非 CNY）→ 中性次色，与各卡主色拉开主次、永不撞色。
        return line.currency == .cny ? cnyTint : FinanceTokens.Text.secondary
    }
}
#endif
