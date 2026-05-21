import SwiftUI

/// Hero 容器 —— 双 style：
/// - `.subtle`（默认，iOS Dashboard hero 用）：单层 brand-soft 径向渐变 + 浅网格，
///   不抢戏，留给金额数字本身做主角。对齐 HTML B 节 `.glass-card` hero。
/// - `.grand`（仅 macOS landing / showcase 用）：三色径向 halo（蓝/紫/橙）+ 网格，
///   对齐 HTML 顶部 hero landing 的 `.hero` 类。
///
/// 注意：HTML 的 macOS Dashboard **不用 HeroPanel**——直接走 KPI 4-col grid。
/// HeroPanel 这个组件主要服务 iOS Dashboard 和 DesignSystem Showcase。
struct HeroPanel<Content: View>: View {
    enum Style {
        case subtle
        case grand
    }

    var style: Style = .subtle
    var padding: CGFloat = FinanceTokens.Spacing.hero
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FinanceTokens.Radius.xl, style: .continuous)
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape
                        .fill(FinanceTokens.Surface.raised)
                        .background(.ultraThinMaterial, in: shape)
                    decorationLayer
                    gridLayer
                }
                .clipShape(shape)
            }
            .overlay {
                shape.stroke(FinanceTokens.Stroke.hairline, lineWidth: 1)
            }
            .clipShape(shape)
            .elevation(.elevated)
    }

    /// 装饰层：subtle 一层 brand-soft 径向，grand 三色 halo。
    @ViewBuilder
    private var decorationLayer: some View {
        switch style {
        case .subtle:
            RadialGradient(
                colors: [FinanceTokens.Brand.primary.opacity(scheme == .dark ? 0.18 : 0.14), .clear],
                center: UnitPoint(x: 0.1, y: 0),
                startRadius: 0,
                endRadius: 460
            )
            .allowsHitTesting(false)
        case .grand:
            ZStack {
                FinanceTokens.Halo.topLeftBlue
                FinanceTokens.Halo.topRightPurple
                FinanceTokens.Halo.bottomRightOrange
            }
            .opacity(scheme == .dark ? 0.65 : 1.0)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    /// 24pt 网格底纹，向边缘淡出。
    private var gridLayer: some View {
        Canvas { ctx, size in
            let stride: CGFloat = 24
            let alpha = scheme == .dark ? 0.05 : 0.03
            let lineColor = Color(white: scheme == .dark ? 1.0 : 0.0).opacity(alpha)
            var path = Path()
            var x: CGFloat = stride
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += stride
            }
            var y: CGFloat = stride
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += stride
            }
            ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
        }
        .mask {
            RadialGradient(
                colors: [.black, .clear],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 40,
                endRadius: 520
            )
        }
        .allowsHitTesting(false)
    }
}
