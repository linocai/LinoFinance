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
