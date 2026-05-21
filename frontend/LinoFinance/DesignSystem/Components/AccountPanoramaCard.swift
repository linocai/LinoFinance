import SwiftUI

/// AccountPanoramaCard 用的过滤选项 —— 提到 generic 外层避免嵌套类型推断错误。
enum AccountPanoramaFilter: String, CaseIterable, Identifiable {
    case all, balance, credit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .balance: "余额"
        case .credit: "信用"
        }
    }
}

/// 账户全景容器 —— 对齐 HTML `.chart-card` 第二张：标题 + segmented 过滤 + 账户行列表。
struct AccountPanoramaCard<Row: View>: View {
    let title: String
    let subtitle: String
    @Binding var filter: AccountPanoramaFilter
    let rows: () -> Row

    init(
        title: String,
        subtitle: String,
        filter: Binding<AccountPanoramaFilter>,
        @ViewBuilder rows: @escaping () -> Row
    ) {
        self.title = title
        self.subtitle = subtitle
        self._filter = filter
        self.rows = rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(FinanceTypography.headline)
                        .foregroundStyle(FinanceTokens.Text.primary)
                    Text(subtitle)
                        .font(FinanceTypography.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                }
                Spacer()
                SegmentedSwitcher(options: AccountPanoramaFilter.allCases, selection: $filter) { $0.title }
                    .frame(maxWidth: 180)
            }

            VStack(spacing: 0) {
                rows()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(strength: .strong, elevation: .elevated)
    }
}
