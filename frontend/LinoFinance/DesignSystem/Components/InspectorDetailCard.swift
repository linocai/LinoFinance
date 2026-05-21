import SwiftUI

/// Inspector 通用详情卡 —— 对齐 HTML `.insp-card`：
/// 圆角 14、Surface.raised 玻璃质感、12px 内边距、soft 阴影。
/// title + meta + content slot。caller 通常往 content 里塞 InspectorKeyValueRow。
struct InspectorDetailCard<Content: View>: View {
    let title: String
    let meta: String?
    let content: () -> Content

    init(
        title: String,
        meta: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.meta = meta
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FinanceTokens.Text.primary)
            if let meta {
                Text(meta)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(FinanceTokens.Text.secondary)
            }
            VStack(spacing: 0) {
                content()
            }
            .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: 14, strength: .strong, elevation: .soft)
    }
}
