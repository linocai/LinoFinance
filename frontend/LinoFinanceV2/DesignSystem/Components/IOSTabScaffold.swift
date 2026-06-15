import SwiftUI

#if os(iOS)

// IOSTabScaffold — iOS bottom TabBar skeleton (HANDOFF §3, plan §E item 8).
//
// No sidebar on iOS. Bottom tab bar = 总览 · 账户 · 〔＋ 记一笔〕· 现金流 · 报表,
// with the center "记一笔" rendered as a raised indigo/violet rounded button.
//
// Px wires the real iOS screens: tabs render their feature views over the bloom
// background; the raised center button presents 记一笔 via `onAddEntry`; a top-
// trailing 「更多」button presents the secondary features (流水 / 报销 / …).

struct IOSTabScaffold<Overview: View, Accounts: View, CashFlow: View, Reports: View, More: View>: View {
    var onAddEntry: () -> Void
    @ViewBuilder var overview: () -> Overview
    @ViewBuilder var accounts: () -> Accounts
    @ViewBuilder var cashFlow: () -> CashFlow
    @ViewBuilder var reports: () -> Reports
    @ViewBuilder var more: () -> More

    @State private var selection: Tab = .overview
    @State private var showMore = false

    enum Tab: Hashable { case overview, accounts, cashFlow, reports }

    var body: some View {
        ZStack(alignment: .bottom) {
            // animated:false — the drifting blobs under .blur(60) recomposite the
            // whole screen every frame forever, which made tab taps feel laggy /
            // unresponsive on device. Static bloom composites once. (All the other
            // iOS screens already pass animated:false; this layer had been missed.)
            BloomBackground(animated: false)

            Group {
                switch selection {
                case .overview: scrollable { overview() }
                case .accounts: scrollable { accounts() }
                case .cashFlow: scrollable { cashFlow() }
                case .reports: scrollable { reports() }
                }
            }

            moreButton
            tabBar
        }
        .sheet(isPresented: $showMore) { more() }
    }

    private var moreButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { showMore = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .frame(width: 40, height: 40)
                        .glassPanel(cornerRadius: 12, shadow: Theme.ShadowSpec(color: .black.opacity(0.06), radius: 10, x: 0, y: 4))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            Spacer()
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
        // Fixed height so the 4 tabs + raised center button lay out consistently
        // (the center cell is exactly 60pt wide → the ➕ is true-centered).
        HStack(alignment: .center, spacing: 0) {
            tabButton(.overview, title: "总览", systemImage: "chart.pie")
            tabButton(.accounts, title: "账户", systemImage: "creditcard")
            addButton
            tabButton(.cashFlow, title: "现金流", systemImage: "arrow.left.arrow.right")
            tabButton(.reports, title: "报表", systemImage: "chart.bar")
        }
        .frame(height: 54)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
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
            // Fill the whole cell + contentShape so the ENTIRE cell is tappable
            // (was icon/text-only → taps on the cell's blank area did nothing, so
            // switching felt laggy / unresponsive).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button(action: onAddEntry) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.Color.brandGradient, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                .themeShadow(Theme.Shadow.brandGlow)
                // Hit area = just the circle, so the raised ➕ can't steal taps
                // meant for the 账户 / 现金流 cells next to it.
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 60)
        .offset(y: -16)   // raised above the bar
    }
}

#endif
