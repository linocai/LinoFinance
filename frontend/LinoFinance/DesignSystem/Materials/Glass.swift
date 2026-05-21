import SwiftUI

/// Liquid Glass 面板背景。
/// - `strength`：玻璃透明度档位（regular / strong / deep，对齐 HTML `--surface-glass` / `--surface-glass-strong` / `--surface-deep`）。
/// - `tint`：可选 brand / semantic 调色，会以 ~14% alpha 薄薄铺一层（对齐 HTML 卡片右上 brand soft 着色）。
/// - `elevation`：透传给统一的 `.elevation()` modifier。传 `nil` 表示父容器已经挂阴影，本层不再叠。
struct GlassBackground: ViewModifier {
    var radius: CGFloat = FinanceTokens.Radius.lg
    var strength: Strength = .regular
    var tint: Color? = nil
    var accent: AnyShapeStyle? = nil
    var elevation: FinanceTokens.Shadow? = .soft

    enum Strength {
        case regular
        case strong
        case deep
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                ZStack {
                    shape
                        .fill(surfaceFill)
                        .background(.ultraThinMaterial, in: shape)
                    if let tint {
                        shape.fill(tint.opacity(0.14))
                    }
                    if let accent {
                        shape.fill(accent)
                    }
                }
            }
            .overlay {
                shape.stroke(FinanceTokens.Stroke.hairline, lineWidth: 1)
            }
            .clipShape(shape)
            .modifier(_OptionalElevation(shadow: elevation))
    }

    private var surfaceFill: Color {
        switch strength {
        case .regular: return FinanceTokens.Surface.glass
        case .strong: return FinanceTokens.Surface.glassStrong
        case .deep: return FinanceTokens.Surface.deepGlass
        }
    }
}

private struct _OptionalElevation: ViewModifier {
    let shadow: FinanceTokens.Shadow?

    func body(content: Content) -> some View {
        if let shadow {
            content.elevation(shadow)
        } else {
            content
        }
    }
}

extension View {
    func glassBackground(
        radius: CGFloat = FinanceTokens.Radius.lg,
        strength: GlassBackground.Strength = .regular,
        tint: Color? = nil,
        accent: AnyShapeStyle? = nil,
        elevation: FinanceTokens.Shadow? = .soft
    ) -> some View {
        modifier(GlassBackground(
            radius: radius,
            strength: strength,
            tint: tint,
            accent: accent,
            elevation: elevation
        ))
    }
}
