import SwiftUI

// TintedActionChip — soft tinted inline action pill (R0, Phase A).
//
// Comp source: lf_chips.png — 确认=淡绿底+绿字 / 兑现=淡蓝底+蓝字 / 取消=淡灰底+灰字.
// A small rounded capsule whose fill is the tone color at low opacity and whose
// label is the tone color (solid). Used for the现金流 inline row actions instead
// of a `⋯` menu + native confirm dialog: each chip fires its action directly.
//
// Tokens (from comp + HANDOFF §2): fill = tone @ 0.12 (light) / 0.20 (dark);
// text = tone (solid); radius 9–10; padding H12 V6; font ~13 medium; light
// hover / press feedback.

struct TintedActionChip: View {
    enum Tone {
        /// confirm / positive — green (`Theme.Color.income`).
        case positive
        /// settle / action — blue (`Theme.Color.link`).
        case action
        /// cancel / neutral — gray (`Theme.Color.textSecondary`).
        case neutral
        /// destructive — red (`Theme.Color.expense`).
        case destructive
        /// brand — indigo/violet (`Theme.Color.brandEnd`).
        case brand

        var color: Color {
            switch self {
            case .positive: Theme.Color.income
            case .action: Theme.Color.link
            case .neutral: Theme.Color.textSecondary
            case .destructive: Theme.Color.expense
            case .brand: Theme.Color.brandEnd
            }
        }
    }

    let title: String
    var systemImage: String?
    var tone: Tone = .neutral
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var pressed = false

    private let radius: CGFloat = 9.5

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(tone.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                tone.color.opacity(fillOpacity),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tone.color.opacity(0.18), lineWidth: 0.5)
            }
            .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
        .onLongPressGesture(minimumDuration: 0, pressing: { p in
            withAnimation(.easeOut(duration: 0.1)) { pressed = p }
        }, perform: {})
    }

    private var fillOpacity: Double {
        let base = scheme == .dark ? 0.20 : 0.12
        return hovering ? base + 0.06 : base
    }
}
