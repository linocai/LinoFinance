import SwiftUI

// StatusBadge — small chip pill for reimbursement / cash-flow / subscription
// state (HANDOFF §2.5, chip radius 6–8). Tinted fill + matching text color.
//
// P1 ships the generic chip + a small `Tone` palette. Feature screens (P3–P5)
// map their concrete status enums onto a `Tone` at the call site; this base
// component does not hardcode any specific status string.

struct StatusBadge: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case positive   // received / settled / active
        case pending    // expected / submitted / waiting
        case warning    // invoice-pending / paused / due-soon
        case negative   // rejected / cancelled / voided
        case brand      // AI / highlighted
        case neutral

        var color: Color {
            switch self {
            case .positive: Theme.Color.income
            case .pending: Theme.Color.link
            case .warning: Theme.fixed(0xE08A1F)
            case .negative: Theme.Color.expense
            case .brand: Theme.Color.brandEnd
            case .neutral: Theme.Color.textSecondary
            }
        }
    }

    var body: some View {
        Text(text)
            .font(Theme.Font.badge(.semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                tone.color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(tone.color.opacity(0.22), lineWidth: 0.5)
            }
    }
}
