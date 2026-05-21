#if DEBUG
import SwiftUI

/// 视觉系统总览 —— 在动 feature 页之前一眼审 4 大新原语。
/// macOS：工具栏 debug 命令；iOS：Settings 隐藏入口（Phase 5 接入）。
struct DesignSystemShowcaseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                typographyLadderSection
                heroSection
                elevationSection
                #if os(macOS)
                sidebarSection
                #endif
                metricChipSection
                iconBadgeSection
                statusTagSection
                gradientTextSection
            }
            .padding(FinanceTokens.Spacing.page)
        }
        .background(CanvasBackground())
        .navigationTitle("DesignSystem · v1.1")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                kicker: "Hero",
                title: "HeroPanel",
                description: "Surface.raised + 三色 halo + 24pt grid + xl(30) 圆角 + elevated 阴影。"
            )
            HeroPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("总余额")
                        .font(FinanceTypography.sectionKicker)
                        .tracking(0.6)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                    Text("¥128,640.50")
                        .font(.system(size: 48, weight: .semibold).monospacedDigit())
                        .heroTracking()
                        .gradientForeground(FinanceTokens.heroNumberGradient)
                    HStack(spacing: 10) {
                        MetricChip(title: "本月收入", value: "+ 18,420", tint: FinanceTokens.State.income)
                        MetricChip(title: "本月支出", value: "− 9,860", tint: FinanceTokens.State.expense)
                        MetricChip(title: "信用负债", value: "12,300", tint: FinanceTokens.State.credit)
                    }
                }
            }
        }
    }

    private var elevationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Elevation", title: "三档阴影")
            HStack(spacing: 16) {
                elevationCard("soft", shadow: .soft)
                elevationCard("elevated", shadow: .elevated)
                elevationCard("floating", shadow: .floating)
            }
        }
    }

    private func elevationCard(_ label: String, shadow: FinanceTokens.Shadow) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(FinanceTypography.pillLabel)
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg, style: .continuous)
                .fill(FinanceTokens.Surface.glassStrong)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg, style: .continuous))
        .elevation(shadow)
    }

    #if os(macOS)
    private var sidebarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Sidebar", title: "SidebarRow 三态")
            VStack(spacing: 4) {
                SidebarRow(title: "总览", systemImage: "rectangle.grid.2x2", isActive: true, badge: "热", action: {})
                SidebarRow(title: "账户", systemImage: "wallet.bifold", isActive: false, badge: "12", action: {})
                SidebarRow(title: "AI 工作台", systemImage: "wand.and.stars", isActive: false, action: {})
                SidebarRow(title: "信用卡", systemImage: "creditcard", isActive: false, badge: "待还", action: {})
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg, style: .continuous)
                    .fill(FinanceTokens.Surface.deepGlass)
            )
        }
    }
    #endif

    private var metricChipSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Chip", title: "MetricChip")
            HStack(spacing: 10) {
                MetricChip(title: "净资产", value: "¥128,640", tint: FinanceTokens.Brand.primary)
                MetricChip(title: "本月入账", value: "+ 18,420", tint: FinanceTokens.State.income)
                MetricChip(title: "本月支出", value: "− 9,860", tint: FinanceTokens.State.expense)
                MetricChip(title: "AI 待确认", value: "3", tint: FinanceTokens.State.ai)
            }
        }
    }

    private var iconBadgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Badge", title: "AccountIconBadge")
            HStack(spacing: 14) {
                AccountIconBadge(systemImage: "banknote", tint: FinanceTokens.State.income)
                AccountIconBadge(systemImage: "creditcard", tint: FinanceTokens.State.credit)
                AccountIconBadge(systemImage: "cart", tint: FinanceTokens.State.expense)
                AccountIconBadge(systemImage: "dollarsign.circle", tint: FinanceTokens.Currency.usd)
                AccountIconBadge(systemImage: "yensign.circle", tint: FinanceTokens.Currency.cny)
                AccountIconBadge(systemImage: "wand.and.stars", tint: FinanceTokens.State.ai)
            }
        }
    }

    private var statusTagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Tag", title: "StatusTag 全谱")
            FlowRow(spacing: 8) {
                StatusTag(title: "Confirmed", style: .confirmed)
                StatusTag(title: "Draft", style: .draft)
                StatusTag(title: "Expected", style: .expected)
                StatusTag(title: "Settled", style: .settled)
                StatusTag(title: "Cancelled", style: .cancelled)
                StatusTag(title: "Expense", style: .expense)
                StatusTag(title: "Income", style: .income)
                StatusTag(title: "Warning", style: .warning)
                StatusTag(title: "AI", style: .ai)
            }
        }
    }

    private var gradientTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: "Type", title: "Gradient Text")
            Text("Liquid Glass · 2026")
                .font(.system(size: 44, weight: .semibold))
                .heroTracking()
                .gradientForeground(FinanceTokens.heroNumberGradient)
        }
    }

    /// 字体阶梯 —— 对照 HTML 第 936-961 行的 type-row 检查 SF Pro 是否到位。
    /// 这是 Phase A 验收的第一站：所有数字、标题都应是 SF Pro（非 Rounded）。
    private var typographyLadderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                kicker: "Type",
                title: "字体阶梯 · SF Pro",
                description: "金额走 monospaced + tnum；大标题 -0.02em 字距；HTML SF Pro，不是 Rounded。"
            )
            VStack(spacing: 14) {
                typeRow(
                    label: "heroNumber",
                    spec: "38 · heavy · -0.025em · mono",
                    demo: AnyView(
                        Text("¥34,712.50")
                            .font(FinanceTypography.heroNumber)
                            .heroTracking()
                            .foregroundStyle(FinanceTokens.Text.primary)
                    )
                )
                typeRow(
                    label: "title.xl",
                    spec: "30 · bold · -0.02em",
                    demo: AnyView(
                        Text("总览")
                            .font(FinanceTypography.titleXL)
                            .titleTracking()
                            .foregroundStyle(FinanceTokens.Text.primary)
                    )
                )
                typeRow(
                    label: "title.l",
                    spec: "26 · bold",
                    demo: AnyView(
                        Text("账户全景")
                            .font(FinanceTypography.titleL)
                            .titleTracking()
                            .foregroundStyle(FinanceTokens.Text.primary)
                    )
                )
                typeRow(
                    label: "headline",
                    spec: "17 · semibold",
                    demo: AnyView(
                        Text("未来 30 天现金流压力")
                            .font(FinanceTypography.headline)
                            .foregroundStyle(FinanceTokens.Text.primary)
                    )
                )
                typeRow(
                    label: "body.mono",
                    spec: "14 · mono · tnum",
                    demo: AnyView(
                        Text("USD 88.00 · 约 ¥598.40")
                            .font(FinanceTypography.bodyMono)
                            .foregroundStyle(FinanceTokens.Text.primary)
                    )
                )
                typeRow(
                    label: "caption",
                    spec: "11.5 · regular · secondary",
                    demo: AnyView(
                        Text("招商银行 · 餐饮 · 2026-05-20")
                            .font(FinanceTypography.caption)
                            .foregroundStyle(FinanceTokens.Text.secondary)
                    )
                )
                typeRow(
                    label: "kicker",
                    spec: "11 · bold · tracking 0.8 · uppercase",
                    demo: AnyView(
                        Text("NET ASSET")
                            .font(FinanceTypography.sectionKicker)
                            .kickerTracking()
                            .foregroundStyle(FinanceTokens.Brand.primary)
                    )
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackground(strength: .strong, elevation: .soft)
        }
    }

    private func typeRow(label: String, spec: String, demo: AnyView) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(FinanceTypography.pillLabel)
                .foregroundStyle(FinanceTokens.Text.tertiary)
                .frame(width: 110, alignment: .leading)
            demo
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(spec)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(FinanceTokens.Text.tertiary)
        }
    }
}

/// 简易 wrap-row —— Showcase 里 tag 谱用，避免引入第三方。
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
#endif
