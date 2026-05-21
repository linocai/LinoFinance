import SwiftUI

/// 隐藏金额按钮 —— 对齐 HTML iOS Hero 右上角 `🔒 隐藏金额` pill。
/// 绑定到 `linofinance.privacyMaskEnabled`（与 PrivacyAmount 共享 AppStorage）。
struct HideAmountButton: View {
    @AppStorage("linofinance.privacyMaskEnabled") private var maskEnabled = false

    var body: some View {
        Button {
            maskEnabled.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: maskEnabled ? "eye.slash" : "lock")
                    .font(.system(size: 10, weight: .semibold))
                Text(maskEnabled ? "已隐藏" : "隐藏金额")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(FinanceTokens.Text.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(FinanceTokens.Surface.glass)
                    .overlay {
                        Capsule().stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(maskEnabled ? "金额已隐藏，点击显示" : "隐藏金额")
    }
}
