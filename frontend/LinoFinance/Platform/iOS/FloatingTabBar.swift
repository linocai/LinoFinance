#if os(iOS)
import SwiftUI

struct FloatingTabBar: View {
    @Binding var selection: iOSTab
    let quickEntry: (QuickEntryIntent) -> Void
    let reimbursement: () -> Void

    private let tabs: [iOSTab] = [.dashboard, .entries, .cashFlow, .credit, .more]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.prefix(2), id: \.self) { tab in
                tabButton(tab)
            }

            fab
                .frame(maxWidth: .infinity)

            ForEach(tabs.suffix(3), id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(FinanceTokens.Stroke.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func tabButton(_ tab: iOSTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selection == tab ? FinanceTokens.Brand.primary : FinanceTokens.Text.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }

    private var fab: some View {
        Button {
            quickEntry(.expense)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(FinanceTokens.Brand.primary))
                .shadow(color: FinanceTokens.Brand.primary.opacity(0.32), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("新建收入") { quickEntry(.income) }
            Button("新建支出") { quickEntry(.expense) }
            Button("新建信用消费") { quickEntry(.creditCharge) }
            Button("新建报销") { reimbursement() }
        }
        .accessibilityLabel("快速记账")
    }
}

extension iOSTab {
    var title: String {
        switch self {
        case .dashboard: "总览"
        case .entries: "记账"
        case .cashFlow: "现金流"
        case .credit: "信用"
        case .more: "更多"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: FinanceModule.dashboard.symbolName
        case .entries: FinanceModule.entries.symbolName
        case .cashFlow: FinanceModule.cashFlow.symbolName
        case .credit: FinanceModule.credit.symbolName
        case .more: "ellipsis.circle.fill"
        }
    }
}
#endif
