import SwiftUI

// SubtleToolbarButton — soft secondary toolbar action (+新建X), R0 Phase A.
//
// Comp source: lf_cashflow.png top-right — a soft glass/faint-filled pill with an
// SF Symbol + label, `textPrimary` ink. Gentle, NOT borderedProminent. Small
// radius ~10.

struct SubtleToolbarButton: View {
    var title: String
    var systemImage: String = "plus"
    var action: () -> Void

    @State private var hovering = false

    private let radius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
            }
            .foregroundStyle(Theme.Color.textPrimary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .glassPanel(cornerRadius: radius, shadow: Theme.ShadowSpec(color: .black.opacity(0.06), radius: 10, x: 0, y: 4))
            .overlay {
                if hovering {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.Color.textSecondary.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
    }
}
