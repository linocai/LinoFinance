import SwiftUI

struct MoneyText: View {
    let amount: DecimalValue
    let currency: CurrencyCode
    var convertedCNY: DecimalValue?
    var prominence: Font = .body

    var body: some View {
        HStack(spacing: 6) {
            Text(FinanceFormatter.money(amount, currency: currency))
                .font(prominence.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let convertedCNY, currency != .cny {
                Text("· \(FinanceFormatter.money(convertedCNY, currency: .cny, approximate: true))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
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
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(Capsule().fill(foreground.opacity(0.12)))
    }

    private var foreground: Color {
        switch style {
        case .draft, .expected:
            return FinanceColor.pending
        case .confirmed, .settled:
            return FinanceColor.income
        case .cancelled:
            return .secondary
        case .expense:
            return FinanceColor.expense
        case .income:
            return FinanceColor.income
        case .warning:
            return .orange
        case .ai:
            return FinanceColor.ai
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
        case "confirmed", "settled", "paid", "received", "executed", "active", "approved":
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
    var tint: Color = FinanceColor.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: FinanceSpacing.cornerRadius))
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
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(FinanceSpacing.panel)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: FinanceSpacing.cornerRadius))
    }
}
