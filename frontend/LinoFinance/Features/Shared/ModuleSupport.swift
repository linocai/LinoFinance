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
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

#if os(iOS)
    private var verticalLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
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
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ToolbarPill: View {
    let title: String
    let value: String
    var tint: Color = FinanceColor.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
#if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
#else
        .background(.regularMaterial)
#endif
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ThinBar: View {
    let value: DecimalValue
    let maxValue: Decimal
    var tint: Color = FinanceColor.brand

    var body: some View {
        GeometryReader { geometry in
            let current = NSDecimalNumber(decimal: value.value).doubleValue
            let maximum = NSDecimalNumber(decimal: maxValue).doubleValue
            let width = maximum <= 0 ? 0 : min(1, current / maximum)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(0.12))
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
            .background(Color(.systemGroupedBackground))
#else
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
