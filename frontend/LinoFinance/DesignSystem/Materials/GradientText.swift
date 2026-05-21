import SwiftUI

/// 给文字（或任何 view）填一层渐变前景 —— 对齐 HTML `background-clip: text`。
/// 实现：先按 view 形状 mask 出一层渐变。
/// 注意：会消费触摸 hit-testing & 部分无障碍 affordance，仅用在 HeroNumber / 大标题，不要挂正文。
struct GradientForeground<G: ShapeStyle>: ViewModifier {
    let gradient: G

    func body(content: Content) -> some View {
        content
            .overlay {
                Rectangle()
                    .fill(gradient)
                    .mask(content)
            }
            .foregroundStyle(.clear)
    }
}

extension View {
    func gradientForeground<G: ShapeStyle>(_ gradient: G) -> some View {
        modifier(GradientForeground(gradient: gradient))
    }
}

extension FinanceTokens {
    /// Hero 数字 / h1 默认渐变（135°，primary → deep）。对齐 HTML hero h1 的 `linear-gradient`。
    static var heroNumberGradient: LinearGradient {
        LinearGradient(
            colors: [Brand.primary, Brand.deep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
