import SwiftUI

#if DEBUG

// DesignSystemShowcaseView — P1 visual sign-off surface (DEBUG only).
//
// Lays out every §E component over the bloom background so a single `open` of the
// v2 app shows the liquid glass for visual sign-off. macOS wraps a demo dashboard
// + a component gallery inside MacGlassScene (floating sidebar visible); iOS uses
// the TabBar skeleton.
//
// Light/dark: the app follows the SYSTEM appearance. To flip during sign-off,
// toggle macOS System Settings ▸ Appearance (or the iOS Simulator's Environment
// Overrides ▸ Interface Style). There is also an in-window scheme toggle button
// below for convenience.

struct DesignSystemShowcaseView: View {
    @State private var selection: SidebarDestination = .overview
    @State private var schemeOverride: ColorScheme? = nil

    var body: some View {
#if os(macOS)
        MacGlassScene(selection: $selection, onAddEntry: {}) {
            gallery
        }
        .preferredColorScheme(schemeOverride)
#else
        IOSTabScaffold(
            onAddEntry: {},
            overview: { gallery },
            accounts: { placeholder("账户") },
            cashFlow: { placeholder("现金流") },
            reports: { placeholder("报表") }
        )
        .preferredColorScheme(schemeOverride)
#endif
    }

    // MARK: - Gallery

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            heroCard
            metricCards
            componentRow
            statusRow
            probeCard
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("总览")
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("DesignSystem 预览 · 液态玻璃")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            schemeToggle
        }
    }

    private var schemeToggle: some View {
        Button {
            switch schemeOverride {
            case .none: schemeOverride = .dark
            case .some(.dark): schemeOverride = .light
            default: schemeOverride = nil
            }
        } label: {
            Label(schemeLabel, systemImage: "circle.lefthalf.filled")
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.link)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassPanel(cornerRadius: Theme.Radius.chip)
        }
        .buttonStyle(.plain)
    }

    private var schemeLabel: String {
        switch schemeOverride {
        case .none: "跟随系统"
        case .some(.dark): "深色"
        default: "浅色"
        }
    }

    // MARK: - Hero (disposable 30d, CNY/USD)

    private var heroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("未来 30 天可支配")
                    .font(Theme.Font.subtitle(.medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                CurrencyAmountView(
                    cny: DecimalValue(Decimal(string: "12840.50")!),
                    usd: DecimalValue(Decimal(string: "1830.00")!),
                    font: Theme.Font.bigNumber()
                )
            }
        }
    }

    // MARK: - Metric cards (net worth tinted + investment + cash flow)

    private var metricCards: some View {
        HStack(alignment: .top, spacing: 16) {
            GlassCard(tint: Theme.Color.brandEnd) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("净资产")
                        .font(Theme.Font.caption(.medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                    CurrencyAmountView(
                        cny: DecimalValue(Decimal(string: "486200.00")!),
                        usd: DecimalValue(Decimal(string: "68200.00")!),
                        axis: .vertical,
                        font: Theme.Font.cardNumber()
                    )
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("投资 · 今日盈亏")
                        .font(Theme.Font.caption(.medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                    AmountText(
                        value: DecimalValue(Decimal(string: "1280.40")!),
                        currency: .cny,
                        showsPositiveSign: true,
                        font: Theme.Font.cardNumber(),
                        color: Theme.Color.income
                    )
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未来 30 天净流入")
                        .font(Theme.Font.caption(.medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                    AmountText(
                        value: DecimalValue(Decimal(string: "-2350.00")!),
                        currency: .cny,
                        font: Theme.Font.cardNumber(),
                        color: Theme.Color.expense
                    )
                }
            }
        }
    }

    // MARK: - Component row (buttons + amount samples)

    private var componentRow: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("组件")
                    .font(Theme.Font.subtitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                HStack(spacing: 16) {
                    PrimaryActionButton(title: "记一笔", action: {})
                        .frame(width: 160)
                    VStack(alignment: .leading, spacing: 6) {
                        AmountText(value: DecimalValue(Decimal(string: "58.00")!), currency: .cny,
                                   font: Theme.Font.body(), color: Theme.Color.expense)
                        AmountText(value: DecimalValue(Decimal(string: "1200.00")!), currency: .usd,
                                   showsPositiveSign: true, font: Theme.Font.body(), color: Theme.Color.income)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Status badges

    private var statusRow: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("状态徽标")
                    .font(Theme.Font.subtitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                HStack(spacing: 8) {
                    StatusBadge(text: "已收款", tone: .positive)
                    StatusBadge(text: "待提交", tone: .pending)
                    StatusBadge(text: "待开票", tone: .warning)
                    StatusBadge(text: "已驳回", tone: .negative)
                    StatusBadge(text: "AI", tone: .brand)
                    StatusBadge(text: "已取消", tone: .neutral)
                }
            }
        }
    }

    // MARK: - P0 API probe (retained as a small card)

    private var probeCard: some View {
        GlassCard {
            ProbeReadout()
        }
    }

    private func placeholder(_ title: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.Font.subtitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("占位 · Px 接真实屏")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }
}

/// Compact reachability readout reused inside the showcase probe card.
private struct ProbeReadout: View {
    @EnvironmentObject private var probe: APIReachabilityProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("连通性探测")
                .font(Theme.Font.subtitle())
                .foregroundStyle(Theme.Color.textPrimary)
            Label(probe.baseURLDescription, systemImage: "network")
                .font(Theme.Font.caption().monospacedDigit())
                .foregroundStyle(Theme.Color.textSecondary)
            Label(probe.statusDescription, systemImage: probe.statusSymbol)
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}

#endif
