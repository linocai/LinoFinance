import SwiftUI

// PrimaryActionButton — the "记一笔" core action (HANDOFF §2.6 + sidebar §2.6).
//
// Indigo→violet gradient (#5B8DEF → #8A6DF0), white text/icon, colored glow shadow.
// This is the single most prominent control in the app and must read clearly apart
// from the plain sidebar nav rows.

struct PrimaryActionButton: View {
    var title: String
    var systemImage: String = "plus"
    /// Compact mode trims padding for the sidebar; full mode for modal CTAs.
    var compact: Bool = false
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 14 : 16, weight: .bold))
                Text(title)
                    .font(Theme.Font.subtitle(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 11 : 14)
            .padding(.horizontal, 14)
            .background(
                Theme.Color.brandGradient,
                in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            }
            .themeShadow(Theme.Shadow.brandGlow)
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { p in
            withAnimation(.easeOut(duration: 0.12)) { pressed = p }
        }, perform: {})
    }
}
