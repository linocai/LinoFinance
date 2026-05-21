import SwiftUI

enum FinanceTokens {
    enum Surface {
        static var base: Color { FinanceTokens.adaptiveColor(light: 0xF5F5F7, dark: 0x0A0A0C) }
        static var deep: Color { FinanceTokens.adaptiveColor(light: 0xEBEBEF, dark: 0x050507) }
        static var raised: Color {
            FinanceTokens.adaptiveColor(
                light: 0xFFFFFF,
                dark: 0x1C1C22,
                lightOpacity: 0.72,
                darkOpacity: 0.72
            )
        }
        static var glass: Color {
            FinanceTokens.adaptiveColor(
                light: 0xFFFFFF,
                dark: 0x28282E,
                lightOpacity: 0.55,
                darkOpacity: 0.55
            )
        }
        static var glassStrong: Color {
            FinanceTokens.adaptiveColor(
                light: 0xFFFFFF,
                dark: 0x323238,
                lightOpacity: 0.82,
                darkOpacity: 0.82
            )
        }
        static var deepGlass: Color {
            FinanceTokens.adaptiveColor(
                light: 0xF5F6FA,
                dark: 0x141418,
                lightOpacity: 0.85,
                darkOpacity: 0.92
            )
        }
    }

    enum Text {
        static var primary: Color { FinanceTokens.adaptiveColor(light: 0x0B0B0F, dark: 0xF5F5F7) }
        static var secondary: Color { FinanceTokens.adaptiveColor(light: 0x6B6B73, dark: 0xA9A9B2) }
        static var tertiary: Color { FinanceTokens.adaptiveColor(light: 0x98989F, dark: 0x72727A) }
    }

    enum Stroke {
        static var hairline: Color {
            FinanceTokens.adaptiveColor(
                light: 0x3C3C43,
                dark: 0xFFFFFF,
                lightOpacity: 0.10,
                darkOpacity: 0.12
            )
        }
        static var soft: Color {
            FinanceTokens.adaptiveColor(
                light: 0x3C3C43,
                dark: 0xFFFFFF,
                lightOpacity: 0.06,
                darkOpacity: 0.08
            )
        }
    }

    enum Brand {
        static var primary: Color { FinanceTokens.adaptiveColor(light: 0x0A84FF, dark: 0x4DA3FF) }
        static var deep: Color { FinanceTokens.adaptiveColor(light: 0x0066CC, dark: 0x7BB9FF) }
        static var soft: Color {
            FinanceTokens.adaptiveColor(
                light: 0x0A84FF,
                dark: 0x4DA3FF,
                lightOpacity: 0.14,
                darkOpacity: 0.18
            )
        }
    }

    enum Currency {
        static var cny: Color { FinanceTokens.adaptiveColor(light: 0xD8324D, dark: 0xFF5C75) }
        static var usd: Color { FinanceTokens.adaptiveColor(light: 0x34A05A, dark: 0x5DCD82) }
    }

    enum State {
        static var income: Color { FinanceTokens.adaptiveColor(light: 0x30B955, dark: 0x54D477) }
        static var expense: Color { FinanceTokens.adaptiveColor(light: 0xE0334A, dark: 0xFF6678) }
        static var credit: Color { FinanceTokens.adaptiveColor(light: 0xFF8A1F, dark: 0xFFAA4D) }
        static var warning: Color { FinanceTokens.adaptiveColor(light: 0xF5C518, dark: 0xFFD95C) }
        static var ai: Color { FinanceTokens.adaptiveColor(light: 0xA557F5, dark: 0xC28AFF) }
        static var pending: Color { Text.tertiary }
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 22
        static let xl: CGFloat = 30
    }

    enum Spacing {
        static var page: CGFloat {
#if os(iOS)
            16
#else
            24
#endif
        }

        static var panel: CGFloat {
#if os(iOS)
            14
#else
            16
#endif
        }

        static let row: CGFloat = 10

        static var hero: CGFloat {
#if os(iOS)
            24
#else
            36
#endif
        }
    }

    /// 三档 elevation —— 每档只挂一层 shadow，禁止 caller 再叠加 `.shadow()`。
    /// 数值对齐 HTML `--shadow-soft / --shadow-elevated / --shadow-floating`，
    /// 颜色基底使用 `rgb(15,23,42)`（slate-900）以匹配 HTML 的冷调投影。
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static var soft: Shadow {
            Shadow(color: slate(lightOpacity: 0.06, darkOpacity: 0.30), radius: 18, x: 0, y: 8)
        }

        static var elevated: Shadow {
            Shadow(color: slate(lightOpacity: 0.18, darkOpacity: 0.50), radius: 26, x: 0, y: 14)
        }

        static var floating: Shadow {
            Shadow(color: slate(lightOpacity: 0.28, darkOpacity: 0.65), radius: 34, x: 0, y: 20)
        }

        /// 按 tint 着色的阴影 —— 用于 FAB / 选中态发光；HTML 中体现为 brand 调色的 shadow。
        static func tinted(_ tint: Color, intensity: Double = 0.32, radius: CGFloat = 22, y: CGFloat = 12) -> Shadow {
            Shadow(color: tint.opacity(intensity), radius: radius, x: 0, y: y)
        }

        private static func slate(lightOpacity: Double, darkOpacity: Double) -> Color {
            FinanceTokens.adaptiveColor(
                light: 0x0F172A,
                dark: 0x000000,
                lightOpacity: lightOpacity,
                darkOpacity: darkOpacity
            )
        }
    }

    /// Hero 容器的三色径向光晕（对齐 HTML `.hero` 的 3 层 radial-gradient）。
    /// 返回 `RadialGradient`，直接当 background / overlay 用。
    enum Halo {
        static var topLeftBlue: RadialGradient {
            RadialGradient(
                colors: [Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.20), .clear],
                center: UnitPoint(x: 0, y: 0),
                startRadius: 0,
                endRadius: 520
            )
        }

        static var topRightPurple: RadialGradient {
            RadialGradient(
                colors: [Color(red: 0.647, green: 0.341, blue: 0.961).opacity(0.18), .clear],
                center: UnitPoint(x: 1, y: 0),
                startRadius: 0,
                endRadius: 420
            )
        }

        static var bottomRightOrange: RadialGradient {
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.541, blue: 0.122).opacity(0.15), .clear],
                center: UnitPoint(x: 0.8, y: 1),
                startRadius: 0,
                endRadius: 380
            )
        }

        /// KPI 卡右上的小角落 brand 光晕（对齐 HTML `.kpi` 的 `radial-gradient(80% 50% at 100% 0%)`）。
        static var brandCorner: RadialGradient {
            RadialGradient(
                colors: [FinanceTokens.Brand.primary.opacity(0.10), .clear],
                center: UnitPoint(x: 1, y: 0),
                startRadius: 0,
                endRadius: 220
            )
        }
    }
}

extension FinanceTokens {
    static func adaptiveColor(
        light: UInt,
        dark: UInt,
        lightOpacity: Double = 1,
        darkOpacity: Double = 1
    ) -> Color {
#if os(iOS)
        Color(UIColor { traitCollection in
            let isDark = traitCollection.userInterfaceStyle == .dark
            return UIColor(
                hex: isDark ? dark : light,
                alpha: isDark ? darkOpacity : lightOpacity
            )
        })
#elseif os(macOS)
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(
                hex: isDark ? dark : light,
                alpha: isDark ? darkOpacity : lightOpacity
            )
        })
#else
        Color(hex: light, alpha: lightOpacity)
#endif
    }
}

enum FinanceColor {
    static var brand: Color { FinanceTokens.Brand.primary }
    static var cny: Color { FinanceTokens.Currency.cny }
    static var usd: Color { FinanceTokens.Currency.usd }
    static var income: Color { FinanceTokens.State.income }
    static var expense: Color { FinanceTokens.State.expense }
    static var credit: Color { FinanceTokens.State.credit }
    static var pending: Color { FinanceTokens.State.pending }
    static var warning: Color { FinanceTokens.State.warning }
    static var ai: Color { FinanceTokens.State.ai }
}

enum FinanceSpacing {
    static var page: CGFloat { FinanceTokens.Spacing.page }
    static var panel: CGFloat { FinanceTokens.Spacing.panel }
    static let row: CGFloat = FinanceTokens.Spacing.row
    static var cornerRadius: CGFloat { FinanceTokens.Radius.md }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

#if os(iOS)
private extension UIColor {
    convenience init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#elseif os(macOS)
private extension NSColor {
    convenience init(hex: UInt, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
