import SwiftUI

/// Inspector 审计卡 —— 对齐 HTML 第 1441-1446 行 `.insp-card` 三行 k-v。
/// 每行：label（事件 + 时间，secondary）+ value（操作者文字 或 StatusTag）。
struct InspectorAuditCard: View {
    let title: String
    let rows: [Row]

    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: Value

        enum Value {
            case text(String, tint: Color)
            case tag(String, style: StatusTag.Style)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FinanceTokens.Text.primary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    InspectorKeyValueRow(label: row.label, showsDivider: index > 0) {
                        switch row.value {
                        case let .text(text, tint):
                            Text(text)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(tint)
                        case let .tag(text, style):
                            StatusTag(title: text, style: style)
                        }
                    }
                }
                if rows.isEmpty {
                    Text("暂无审计记录")
                        .font(.system(size: 11.5))
                        .foregroundStyle(FinanceTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
            }
            .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: 14, strength: .strong, elevation: .soft)
    }
}
