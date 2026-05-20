import SwiftUI

struct GlassBackground: ViewModifier {
    var radius: CGFloat = FinanceTokens.Radius.lg
    var strength: Strength = .regular

    enum Strength {
        case regular
        case strong
    }

    func body(content: Content) -> some View {
        content
            .background(surface)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(FinanceTokens.Stroke.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
    }

    private var surface: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(strength == .strong ? FinanceTokens.Surface.glassStrong : FinanceTokens.Surface.glass)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var shadowOpacity: Double {
#if os(iOS)
        0.07
#else
        0.09
#endif
    }
}

extension View {
    func glassBackground(
        radius: CGFloat = FinanceTokens.Radius.lg,
        strength: GlassBackground.Strength = .regular
    ) -> some View {
        modifier(GlassBackground(radius: radius, strength: strength))
    }
}
