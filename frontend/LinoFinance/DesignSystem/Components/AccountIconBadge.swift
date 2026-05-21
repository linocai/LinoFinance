import SwiftUI

/// 36×36 圆角彩色 icon 徽章 —— 对齐 HTML `.account .icon` / `.entry .icon`。
/// `tint` 的 14-18% alpha 作为底色，全色 tint 作为前景。所有 Account / Entry / Credit 行通吃。
struct AccountIconBadge: View {
    let systemImage: String
    var tint: Color = FinanceTokens.Brand.primary
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }
}
