import SwiftUI

/// 字体阶梯 —— 对齐 HTML `v1.1前端升级预览.html` 第 936-961 行的 type-row 演示。
/// 关键点：
/// 1. **全部走 SF Pro（系统默认 `design: .default`），不用 `.rounded`**。
/// 2. 所有数字 / 英文走 `Font.sfFinance(...)`，启用 `ss01 + cv11 + tnum` 三个 OpenType
///    features —— 对齐 HTML `font-feature-settings: "ss01" on, "cv11" on, "tnum" on`。
/// 3. 大号标题在调用方加 `.titleTracking()` / `.heroTracking()` 收紧字距
///    （HTML `letter-spacing: -0.02em` / `-0.025em`）。
enum FinanceTypography {
    /// 38pt semibold mono —— iOS Dashboard 净资产 hero 数字。
    static var heroNumber: Font { Font.sfFinance(size: 38, weight: .semibold, monospaced: true) }

    /// 22pt semibold mono —— KPI 卡 / 列表大数字。
    static var statValue: Font { Font.sfFinance(size: 22, weight: .semibold, monospaced: true) }

    /// 30pt semibold —— 主页面 h2。
    static var titleXL: Font { Font.sfFinance(size: 30, weight: .semibold) }

    /// 26pt semibold —— 章节大标题。
    static var titleL: Font { Font.sfFinance(size: 26, weight: .semibold) }

    /// 17pt medium —— 卡片标题、列表标题。
    static var headline: Font { Font.sfFinance(size: 17, weight: .medium) }

    /// 14pt mono —— 行内金额、原币转换值。
    static var bodyMono: Font { Font.sfFinance(size: 14, weight: .regular, monospaced: true) }

    /// 11.5pt regular —— 次级说明文本。
    static var caption: Font { Font.sfFinance(size: 11.5, weight: .regular) }

    /// 11pt semibold —— uppercase kicker / eyebrow。
    static var sectionKicker: Font { Font.sfFinance(size: 11, weight: .semibold) }

    /// 11pt medium —— 标签 pill 内文。
    static var pillLabel: Font { Font.sfFinance(size: 11, weight: .medium) }
}

extension Text {
    /// 给 hero 大数字收紧字距（HTML hero: letter-spacing: -0.025em，38pt × -0.025 ≈ -0.95pt）。
    func heroTracking() -> Text { tracking(-1) }

    /// 给大标题收紧字距（HTML titleXL: letter-spacing: -0.02em，30pt × -0.02 ≈ -0.6pt）。
    func titleTracking() -> Text { tracking(-0.6) }

    /// kicker tracking（HTML `.kicker`: letter-spacing: 0.4-0.8px uppercase）。
    func kickerTracking() -> Text { tracking(0.8) }
}
