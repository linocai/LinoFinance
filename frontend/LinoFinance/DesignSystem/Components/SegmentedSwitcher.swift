import SwiftUI

/// 段控制器 —— 对齐 HTML `.seg`：glass 半透明底 + active 段 raised 白底 + soft shadow。
/// 比 SwiftUI 自带的 `Picker.segmented` 更紧凑、更"卡片"，宽度自适应内容。
struct SegmentedSwitcher<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(option == selection ? FinanceTokens.Text.primary : FinanceTokens.Text.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(option == selection ? AnyShapeStyle(FinanceTokens.Surface.raised) : AnyShapeStyle(Color.clear))
                                .overlay {
                                    if option == selection {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                                    }
                                }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(FinanceTokens.Surface.glass)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                }
        )
    }
}
