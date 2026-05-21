import SwiftUI

/// Inspector 卡片内的 k-v 行 —— 对齐 HTML `.insp-row`：
/// 左：caption secondary；右：mono primary。可选 leading 边线（首行无边）。
struct InspectorKeyValueRow<Value: View>: View {
    let label: String
    let showsDivider: Bool
    @ViewBuilder var value: () -> Value

    init(
        label: String,
        showsDivider: Bool = true,
        @ViewBuilder value: @escaping () -> Value
    ) {
        self.label = label
        self.showsDivider = showsDivider
        self.value = value
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Rectangle()
                    .fill(FinanceTokens.Stroke.soft)
                    .frame(height: 0.5)
            }
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(FinanceTokens.Text.secondary)
                Spacer(minLength: 6)
                value()
            }
            .padding(.vertical, 8)
        }
    }
}

/// 便利构造：value 是字符串时直接用 mono primary 渲染。
extension InspectorKeyValueRow where Value == Text {
    init(label: String, value: String, showsDivider: Bool = true) {
        self.init(label: label, showsDivider: showsDivider) {
            Text(value)
        }
    }
}
