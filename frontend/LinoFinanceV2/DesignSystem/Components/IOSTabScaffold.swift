import SwiftUI

#if os(iOS)

// IOSTabScaffold — iOS bottom TabBar skeleton (HANDOFF §3, plan §E item 8).
//
// No sidebar on iOS. Bottom tab bar = 总览 · 账户 · 〔＋ 记一笔〕· 现金流 · 报表,
// with the center "记一笔" rendered as a raised indigo/violet rounded button.
//
// P1 ships the SKELETON only: tabs render with placeholder content over the bloom
// background; the raised center button calls `onAddEntry`. Real screens land in Px.

struct IOSTabScaffold<Overview: View, Accounts: View, CashFlow: View, Reports: View>: View {
    var onAddEntry: () -> Void
    @ViewBuilder var overview: () -> Overview
    @ViewBuilder var accounts: () -> Accounts
    @ViewBuilder var cashFlow: () -> CashFlow
    @ViewBuilder var reports: () -> Reports

    @State private var selection: Tab = .overview

    enum Tab: Hashable { case overview, accounts, cashFlow, reports }

    var body: some View {
        ZStack(alignment: .bottom) {
            BloomBackground()

            Group {
                switch selection {
                case .overview: scrollable { overview() }
                case .accounts: scrollable { accounts() }
                case .cashFlow: scrollable { cashFlow() }
                case .reports: scrollable { reports() }
                }
            }

            tabBar
        }
    }

    private func scrollable<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        ScrollView {
            c()
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 110)   // clear the floating tab bar
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tabBar: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.overview, title: "总览", systemImage: "chart.pie")
            tabButton(.accounts, title: "账户", systemImage: "creditcard")
            addButton
            tabButton(.cashFlow, title: "现金流", systemImage: "arrow.left.arrow.right")
            tabButton(.reports, title: "报表", systemImage: "chart.bar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .glassPanel(cornerRadius: 26, shadow: Theme.Shadow.sidebar)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tab: Tab, title: String, systemImage: String) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selected ? Theme.Color.brandEnd : Theme.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button(action: onAddEntry) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Theme.Color.brandGradient, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                .themeShadow(Theme.Shadow.brandGlow)
        }
        .buttonStyle(.plain)
        .offset(y: -14)   // raised above the bar
        .frame(width: 64)
    }
}

#endif
