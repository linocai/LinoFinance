import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 把 SF Pro 的 OpenType features (`ss01 + cv11 + tnum`) 装进 SwiftUI `Font`。
/// 对齐 HTML `body { font-feature-settings: "ss01" on, "cv11" on, "tnum" on; }`。
///
/// 这些 feature 影响 SF Pro 数字 4 / 6 / 9 / a / g / l / R 等字形 ——
/// 让数字/英文看起来更"打字稿"、更 typographic。
extension Font {
    /// 返回一个开了 ss01 + cv11 的系统 SF Pro Font；如果 `monospaced` 为 true 同时开 tnum。
    /// 失败兜底：返回 `.system(size:weight:)` + `.monospacedDigit()`（如需）。
    static func sfFinance(size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
#if os(iOS)
        let uiWeight = uiFontWeight(weight)
        let baseFont = UIFont.systemFont(ofSize: size, weight: uiWeight)
        let features = featureSettings(monospaced: monospaced)
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName.featureSettings: features
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        return Font(font)
#elseif os(macOS)
        let nsWeight = nsFontWeight(weight)
        let baseFont = NSFont.systemFont(ofSize: size, weight: nsWeight)
        let features = featureSettings(monospaced: monospaced)
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName.featureSettings: features
        ])
        if let font = NSFont(descriptor: descriptor, size: size) {
            return Font(font)
        }
        // Fallback
        var fb = Font.system(size: size, weight: weight)
        if monospaced { fb = fb.monospacedDigit() }
        return fb
#else
        var fb = Font.system(size: size, weight: weight)
        if monospaced { fb = fb.monospacedDigit() }
        return fb
#endif
    }

    /// 三个 feature 字典数组：
    ///   - ss01: type 35 (Stylistic Alternatives), selector 2 (Stylistic Alt One On)
    ///   - cv11: type 37 (Character Alternatives), selector 11
    ///   - tnum: type 6  (Number Spacing), selector 0 (Monospaced Numbers)
    private static func featureSettings(monospaced: Bool) -> [[String: Int]] {
        // CoreText / UIFontDescriptor.FeatureKey 的 raw value 在两平台一致；
        // 用裸字符串 key 是为了避免 Swift macros 让 .type / .selector 在某些 SDK 上不可用。
        let kType = "CTFeatureTypeIdentifier"
        let kSelector = "CTFeatureSelectorIdentifier"
        var settings: [[String: Int]] = [
            [kType: 35, kSelector: 2],  // ss01
            [kType: 37, kSelector: 11]  // cv11
        ]
        if monospaced {
            settings.append([kType: 6, kSelector: 0])  // tnum
        }
        return settings
    }

#if os(iOS)
    private static func uiFontWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
#elseif os(macOS)
    private static func nsFontWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
#endif
}
