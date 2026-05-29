import SwiftUI

struct MoneyText: View {
    let amount: DecimalValue
    let currency: CurrencyCode
    var convertedCNY: DecimalValue?
    var prominence: Font = .body

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalContent
#if os(iOS)
            verticalContent
#endif
        }
    }

    private var horizontalContent: some View {
        HStack(spacing: 6) {
            primaryAmount
            convertedAmount(prefix: "· ")
        }
    }

#if os(iOS)
    private var verticalContent: some View {
        VStack(alignment: .trailing, spacing: 2) {
            primaryAmount
            convertedAmount(prefix: "")
        }
    }
#endif

    private var primaryAmount: some View {
        PrivacyAmount(
            value: FinanceFormatter.money(amount, currency: currency),
            font: prominence.monospacedDigit()
        )
    }

    @ViewBuilder
    private func convertedAmount(prefix: String) -> some View {
        if let convertedCNY, currency != .cny {
            PrivacyAmount(
                value: "\(prefix)\(FinanceFormatter.money(convertedCNY, currency: .cny, approximate: true))",
                font: .subheadline.monospacedDigit(),
                tint: FinanceTokens.Text.secondary,
                alignment: .trailing
            )
        }
    }
}

struct StatusTag: View {
    let title: String
    let style: Style

    enum Style {
        case draft
        case confirmed
        case expected
        case settled
        case cancelled
        case expense
        case income
        case warning
        case ai
    }

    var body: some View {
        Text(title)
            .font(FinanceTypography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(Capsule().fill(foreground.opacity(0.14)))
            .overlay {
                Capsule().stroke(foreground.opacity(0.18), lineWidth: 1)
            }
    }

    private var foreground: Color {
        switch style {
        case .draft, .expected:
            return FinanceTokens.State.pending
        case .confirmed:
            return FinanceTokens.State.income
        case .settled:
            // Settled = terminal/done. Use the muted tertiary tone so it
            // visually retreats next to active 已确认 / 已收到 rows.
            return FinanceTokens.Text.tertiary
        case .cancelled:
            return FinanceTokens.Text.tertiary
        case .expense:
            return FinanceTokens.State.expense
        case .income:
            return FinanceTokens.State.income
        case .warning:
            return FinanceTokens.State.warning
        case .ai:
            return FinanceTokens.State.ai
        }
    }
}

extension StatusTag {
    init(status: String) {
        self.title = status.financeStatusTitle
        self.style = .from(status)
    }
}

extension StatusTag.Style {
    static func from(_ status: String) -> StatusTag.Style {
        switch status {
        case "settled":
            return .settled
        case "confirmed", "paid", "received", "executed", "active", "approved", "published":
            return .confirmed
        case "expected", "draft", "pending", "open", "requires_confirmation", "auto_confirm_candidate":
            return .draft
        case "cancelled", "canceled", "voided", "abandoned", "rejected", "rolled_back", "skipped", "paused":
            return .cancelled
        case "outflow", "expense", "overdue", "failed":
            return .expense
        case "inflow", "income":
            return .income
        case "medium", "high", "partially_paid", "partial_received", "warning":
            return .warning
        default:
            return .expected
        }
    }
}

struct KPIStat: View {
    let title: String
    let value: String
    var systemImage: String
    var tint: Color = FinanceTokens.Brand.primary
    var accent: RadialGradient? = nil
    @AppStorage("linofinance.useHeroNumbers") private var useHeroNumbers = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
            }
            if useHeroNumbers {
                HeroNumber(value: value, tint: FinanceTokens.Text.primary)
            } else {
                PrivacyAmount(
                    value: value,
                    font: .title2.weight(.semibold).monospacedDigit(),
                    tint: FinanceTokens.Text.primary
                )
            }
            Text(title)
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
        .padding(FinanceTokens.Spacing.panel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(
            radius: FinanceTokens.Radius.lg,
            accent: accent.map { AnyShapeStyle($0) },
            elevation: .soft
        )
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(FinanceTokens.Text.tertiary)
            Text(title)
                .font(FinanceTypography.headline)
                .foregroundStyle(FinanceTokens.Text.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(FinanceTokens.Text.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(minHeight: 180, alignment: .top)
        .padding()
    }
}

struct FinancePanel<Content: View>: View {
    var radius: CGFloat = FinanceTokens.Radius.lg
    var strength: GlassBackground.Strength = .regular
    var elevation: FinanceTokens.Shadow? = .soft
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(FinanceTokens.Spacing.panel)
#if os(iOS)
            .frame(maxWidth: .infinity, alignment: .leading)
#endif
            .glassBackground(radius: radius, strength: strength, elevation: elevation)
    }
}
