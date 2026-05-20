import SwiftUI

struct ConfirmAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let role: ButtonRole?
    let action: () -> Void
}

struct DetailLine: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLine
#if os(iOS)
            verticalLine
#endif
        }
    }

    private var horizontalLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
            Spacer()
            Text(value)
                .font(FinanceTypography.bodyMono)
                .foregroundStyle(FinanceTokens.Text.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

#if os(iOS)
    private var verticalLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
            Text(value)
                .font(FinanceTypography.bodyMono)
                .foregroundStyle(FinanceTokens.Text.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
#endif
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(FinanceTokens.State.warning)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FinanceTokens.State.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.sm))
    }
}

struct ToolbarPill: View {
    let title: String
    let value: String
    var tint: Color = FinanceTokens.Brand.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
            PrivacyAmount(
                value: value,
                font: .headline.monospacedDigit(),
                tint: tint
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: FinanceTokens.Radius.md, strength: .strong)
    }
}

struct ThinBar: View {
    let value: DecimalValue
    let maxValue: Decimal
    var tint: Color = FinanceTokens.Brand.primary

    var body: some View {
        GeometryReader { geometry in
            let current = NSDecimalNumber(decimal: value.value).doubleValue
            let maximum = NSDecimalNumber(decimal: maxValue).doubleValue
            let width = maximum <= 0 ? 0 : min(1, current / maximum)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(FinanceTokens.Stroke.soft)
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint.opacity(0.75))
                    .frame(width: geometry.size.width * width)
            }
        }
        .frame(height: 8)
    }
}

extension View {
    func moduleFrame() -> some View {
#if os(iOS)
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(FinanceTokens.Surface.base)
#else
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(FinanceTokens.Surface.base)
#endif
    }
}

extension Array where Element == AccountDTO {
    var balanceAccounts: [AccountDTO] {
        filter { $0.type == .balance }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }

    var creditAccounts: [AccountDTO] {
        filter { $0.type == .credit }
            .sorted { $0.displayOrder == $1.displayOrder ? $0.name < $1.name : $0.displayOrder < $1.displayOrder }
    }
}
