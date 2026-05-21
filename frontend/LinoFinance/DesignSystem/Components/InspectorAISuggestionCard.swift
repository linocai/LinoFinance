import SwiftUI

/// Inspector AI 建议卡 —— 对齐 HTML 第 1431-1439 行：
/// 紫蓝渐变背景 + ✦ 紫色 icon + title + meta + 12.5pt body + 两个 pill 按钮
/// （主按钮"采纳"用 brand 实底白字，次按钮"忽略"用 glass-strong）。
struct InspectorAISuggestionCard: View {
    let title: String
    let meta: String?
    let message: String
    var primaryActionTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FinanceTokens.State.ai)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FinanceTokens.Text.primary)
                    .lineLimit(2)
            }
            if let meta {
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            Text(message)
                .font(.system(size: 12.5))
                .lineSpacing(2.5)
                .foregroundStyle(FinanceTokens.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: 6) {
                    if let primaryActionTitle, let primaryAction {
                        Button(action: primaryAction) {
                            Text(primaryActionTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(FinanceTokens.Brand.primary))
                        }
                        .buttonStyle(.plain)
                    }
                    if let secondaryActionTitle, let secondaryAction {
                        Button(action: secondaryAction) {
                            Text(secondaryActionTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(FinanceTokens.Text.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(FinanceTokens.Surface.glassStrong)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                                        }
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            FinanceTokens.State.ai.opacity(0.18),
                            FinanceTokens.Brand.primary.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .elevation(.soft)
    }
}
