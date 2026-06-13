import SwiftUI

// LinoFinance v2 — Liquid Glass design tokens.
//
// Authority: HANDOFF.md §2 (exact rgba values). This is the v2 visual language —
// indigo/violet brand gradient + real `.glassEffect` (NOT v1's blue + ultraThinMaterial).
//
// Light/dark colors follow the system appearance via dynamic NSColor/UIColor
// (the v1 `adaptiveColor` idiom). This is a deliberate deviation from §E's literal
// "Asset Catalog Any/Dark" — see P1 report. Dynamic colors give exact rgba control
// and avoid an extra asset bundle; behavior (follows system, supports preview
// override via `.preferredColorScheme`) is identical.

enum Theme {

    // MARK: - Colors (HANDOFF §2.2)

    enum Color {
        // Text
        /// Primary label — light `#1C1C1E`, dark `#F5F5F7`.
        static var textPrimary: SwiftUI.Color { dynamic(light: 0x1C1C1E, dark: 0xF5F5F7) }
        /// Secondary label — light `rgba(60,60,67,0.6)`, dark `rgba(235,235,245,0.6)`.
        static var textSecondary: SwiftUI.Color {
            dynamic(light: 0x3C3C43, dark: 0xEBEBF5, lightAlpha: 0.6, darkAlpha: 0.6)
        }
        /// Tertiary label — light `rgba(60,60,67,0.3)`, dark `rgba(235,235,245,0.3)`.
        static var textTertiary: SwiftUI.Color {
            dynamic(light: 0x3C3C43, dark: 0xEBEBF5, lightAlpha: 0.3, darkAlpha: 0.3)
        }

        // Semantic value colors
        /// Income / positive — light green `#1F9D57`, dark `#30D158`.
        static var income: SwiftUI.Color { dynamic(light: 0x1F9D57, dark: 0x30D158) }
        /// Expense / negative — light red `#E0483D`, dark `#FF6961`.
        static var expense: SwiftUI.Color { dynamic(light: 0xE0483D, dark: 0xFF6961) }
        /// Expense emphasis (e.g. large outflow numbers) — `#C2403A`.
        static var expenseStrong: SwiftUI.Color { dynamic(light: 0xC2403A, dark: 0xFF6961) }
        /// Secondary action link — blue `#2D6FF2`.
        static var link: SwiftUI.Color { dynamic(light: 0x2D6FF2, dark: 0x5B9BFF) }

        // Brand (indigo→violet gradient endpoints, HANDOFF §2.2)
        static var brandStart: SwiftUI.Color { fixed(0x5B8DEF) }
        static var brandEnd: SwiftUI.Color { fixed(0x8A6DF0) }

        /// Indigo→violet brand gradient — the v2 accent (记一笔 button, progress, net-worth/AI cards).
        static var brandGradient: LinearGradient {
            LinearGradient(
                colors: [brandStart, brandEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Soft brand tint for selected sidebar rows / chips (light tint over glass).
        static var brandSoft: SwiftUI.Color {
            dynamic(light: 0x5B8DEF, dark: 0x8A6DF0, lightAlpha: 0.14, darkAlpha: 0.22)
        }

        // Currency accents (CNY / USD — kept distinct & equal-weight, §5)
        static var cny: SwiftUI.Color { income }   // CNY reads as the home currency green family
        static var usd: SwiftUI.Color { link }     // USD reads as the blue link family

        // Glass surfaces
        /// Glass panel fill — light `rgba(255,255,255,0.55)`, dark `rgba(50,50,58,0.42)`.
        static var glassFill: SwiftUI.Color {
            dynamic(light: 0xFFFFFF, dark: 0x32323A, lightAlpha: 0.55, darkAlpha: 0.42)
        }
        /// 0.5pt hairline edge on glass panels — light `rgba(60,60,67,0.10)`, dark `rgba(255,255,255,0.12)`.
        static var glassStroke: SwiftUI.Color {
            dynamic(light: 0x3C3C43, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.12)
        }
        /// Top inset white highlight on glass panels.
        static var glassHighlight: SwiftUI.Color {
            dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.55, darkAlpha: 0.18)
        }

        /// Faint 0.5pt list-row divider (HANDOFF §2.5).
        static var divider: SwiftUI.Color {
            dynamic(light: 0x3C3C43, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.10)
        }
    }

    // MARK: - Bloom palette (HANDOFF §2.3 — colored light blobs for glass refraction)

    enum Bloom {
        static var orange: SwiftUI.Color { SwiftUI.Color(.sRGB, red: 255/255, green: 176/255, blue: 120/255, opacity: 1) }
        static var blue: SwiftUI.Color { SwiftUI.Color(.sRGB, red: 120/255, green: 170/255, blue: 255/255, opacity: 1) }
        static var violet: SwiftUI.Color { SwiftUI.Color(.sRGB, red: 190/255, green: 150/255, blue: 255/255, opacity: 1) }
    }

    // MARK: - Typography (HANDOFF §2.4 — pt sizes, system font, monospaced digits for amounts)

    enum Font {
        /// iPhone hero number (~76pt).
        static func hero(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { .system(size: 76, weight: weight) }
        /// Large dashboard number (~66pt).
        static func bigNumber(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { .system(size: 66, weight: weight) }
        /// Card primary number (~27pt).
        static func cardNumber(_ weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font { .system(size: 27, weight: weight) }
        /// Page title (~24pt).
        static func pageTitle(_ weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font { .system(size: 24, weight: weight) }
        /// Section / card subtitle (15–16pt).
        static func subtitle(_ weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font { .system(size: 15.5, weight: weight) }
        /// Body (14–15pt).
        static func body(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font { .system(size: 14.5, weight: weight) }
        /// Secondary / caption (12.5–13pt).
        static func caption(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font { .system(size: 12.5, weight: weight) }
        /// Badge / corner label (~11pt).
        static func badge(_ weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font { .system(size: 11, weight: weight) }
    }

    // MARK: - Corner radii (HANDOFF §2.5)

    enum Radius {
        static let window: CGFloat = 20
        static let card: CGFloat = 16
        static let sidebar: CGFloat = 22
        static let button: CGFloat = 13
        static let chip: CGFloat = 7
    }

    // MARK: - Shadows (HANDOFF §2.5 — soft, large, low-opacity)

    enum Shadow {
        /// Content-card shadow: `y 8–10, blur 26, black 8%`.
        static let card = ShadowSpec(color: .black.opacity(0.08), radius: 26, x: 0, y: 9)
        /// Floating sidebar — heavier.
        static let sidebar = ShadowSpec(color: .black.opacity(0.16), radius: 34, x: 0, y: 18)
        /// Colored glow under the indigo/violet 记一笔 button.
        static let brandGlow = ShadowSpec(color: Color.brandEnd.opacity(0.45), radius: 20, x: 0, y: 10)
    }

    struct ShadowSpec {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: - Dynamic color helper (v1 adaptiveColor idiom)

    static func dynamic(
        light: UInt,
        dark: UInt,
        lightAlpha: Double = 1,
        darkAlpha: Double = 1
    ) -> SwiftUI.Color {
#if os(iOS)
        SwiftUI.Color(UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
#elseif os(macOS)
        SwiftUI.Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
#else
        SwiftUI.Color(hex: light, alpha: lightAlpha)
#endif
    }

    /// Appearance-independent fixed color (brand gradient endpoints render the same in both modes).
    static func fixed(_ hex: UInt, alpha: Double = 1) -> SwiftUI.Color {
        SwiftUI.Color(hex: hex, alpha: alpha)
    }
}

// MARK: - Shadow application

extension View {
    /// Apply a `Theme.ShadowSpec` as a single `.shadow()`.
    func themeShadow(_ spec: Theme.ShadowSpec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }
}

// MARK: - Hex initializers

extension Color {
    fileprivate init(hex: UInt, alpha: Double = 1) {
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
extension UIColor {
    fileprivate convenience init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#elseif os(macOS)
extension NSColor {
    fileprivate convenience init(hex: UInt, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
