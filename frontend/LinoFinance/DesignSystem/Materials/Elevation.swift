import SwiftUI

/// 三档 elevation 修饰符 —— 唯一的 shadow 入口。
/// Feature 层禁用 `.shadow(...)` 直调，统一走 `.elevation(.soft / .elevated / .floating)`。
struct ElevationModifier: ViewModifier {
    let shadow: FinanceTokens.Shadow

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

extension View {
    func elevation(_ shadow: FinanceTokens.Shadow) -> some View {
        modifier(ElevationModifier(shadow: shadow))
    }
}
