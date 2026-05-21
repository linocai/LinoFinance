import SwiftUI

/// 36×36 圆角 icon tile —— 对齐 HTML `.icon`（账户行、KPI 卡顶部、Inspector 卡）。
/// `tint` 的 ~16% alpha 作为底色，全色 tint 作为前景。
/// 与 AccountIconBadge 的区别：tile 默认 36pt + 11pt 圆角，badge 可自定义 size。
/// 这是 HTML 优先版本，feature 页统一调用这个。
struct AccountIconTile: View {
    let systemImage: String
    var tint: Color = FinanceTokens.Brand.primary
    var size: CGFloat = 36
    var radius: CGFloat = 11

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .regular))
                    .foregroundStyle(tint)
            }
    }
}
