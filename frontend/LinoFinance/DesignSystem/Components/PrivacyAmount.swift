import SwiftUI

struct PrivacyAmount: View {
    let value: String
    var font: Font = FinanceTypography.bodyMono
    var tint: Color = FinanceTokens.Text.primary
    var alignment: TextAlignment = .leading

    @AppStorage("linofinance.privacyMaskEnabled") private var privacyMaskEnabled = false
    @AppStorage("linofinance.privacyLocked") private var privacyLocked = false
    @State private var isTemporarilyRevealed = false
    @State private var isHovering = false

    var body: some View {
        Text(displayValue)
            .font(font)
            .foregroundStyle(tint)
            .multilineTextAlignment(alignment)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: isMasked ? 2.4 : 0)
            .privacySensitive(isMasked)
            .onLongPressGesture(minimumDuration: 0.35) {
                revealBriefly()
            }
#if os(macOS)
            .onHover { hovering in
                isHovering = hovering
            }
#endif
    }

    private var isMasked: Bool {
        privacyMaskEnabled && privacyLocked && !isTemporarilyRevealed && !isHovering
    }

    private var displayValue: String {
        isMasked ? maskedValue : value
    }

    private var maskedValue: String {
        let visibleCurrency = value.prefix { !$0.isNumber && $0 != "." && $0 != "," && $0 != "-" }
        let prefix = visibleCurrency.isEmpty ? "" : "\(visibleCurrency)"
        return "\(prefix)•••• ••••"
    }

    private func revealBriefly() {
        isTemporarilyRevealed = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                isTemporarilyRevealed = false
            }
        }
    }
}
