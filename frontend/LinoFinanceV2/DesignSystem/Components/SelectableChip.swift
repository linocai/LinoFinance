import SwiftUI

// SelectableChip — single-select chip for category pickers etc., R0 Phase A.
//
// Comp source: lf_addentry.png — the 分类 row is a flow of small chips; the chosen
// one is a solid dark (`textPrimary`) pill with reverse-ink text, the rest are a
// faint fill with `textPrimary` text. Radius ~9.

struct SelectableChip: View {
    let title: String
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    private let radius: CGFloat = 9

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Theme.Color.inkButtonText : Theme.Color.textPrimary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(background)
                .overlay {
                    if !isSelected {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.Color.glassStroke, lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.Color.textPrimary)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.Color.textSecondary.opacity(hovering ? 0.14 : 0.08))
        }
    }
}
