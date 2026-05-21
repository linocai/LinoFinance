import SwiftUI

/// AI 月报卡 —— 对齐 HTML iOS Dashboard 第 1062-... 行 `.glass-card with gradient`：
/// 紫蓝渐变背景 + ✦ 图标 + 月份 title + 节选 body + 两个 pill 按钮（展开 / 导出 PDF）。
struct AIMonthlyReportCard: View {
    let title: String
    let excerpt: String
    var expandAction: (() -> Void)? = nil
    var exportAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AccountIconTile(systemImage: "sparkles", tint: FinanceTokens.State.ai, size: 28, radius: 8)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FinanceTokens.Text.primary)
            }

            Text(excerpt)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(FinanceTokens.Text.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let expandAction {
                    Button(action: expandAction) {
                        Text("展开全文")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(FinanceTokens.Brand.primary))
                    }
                    .buttonStyle(.plain)
                }
                if let exportAction {
                    Button(action: exportAction) {
                        Text("导出 PDF")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FinanceTokens.Text.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(FinanceTokens.Surface.glassStrong)
                                    .overlay {
                                        Capsule().stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                                    }
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            FinanceTokens.State.ai.opacity(0.20),
                            FinanceTokens.Brand.primary.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg, style: .continuous)
                .stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg, style: .continuous))
        .elevation(.soft)
    }
}
