import SwiftUI

// SegmentedPill — segmented selector replacing the native `Picker(.segmented)`,
// R0 Phase A.
//
// Comp source: lf_seg.png — a light-gray capsule track; the selected segment is a
// solid dark (`textPrimary`) pill with reverse-ink text; unselected segments are
// `textSecondary` text on the bare track. Animated selection slide.
//
// Generic over any `Hashable & Identifiable` option; the caller maps each option
// to a title via `title`.

struct SegmentedPill<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    @Namespace private var pillNamespace

    private let trackRadius: CGFloat = 11
    private let pillRadius: CGFloat = 9

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(4)
        .background(
            Theme.Color.textSecondary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
        )
    }

    private func segment(_ option: T) -> some View {
        let isSelected = option == selection
        return Text(title(option))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? Theme.Color.inkButtonText : Theme.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                        .fill(Theme.Color.textPrimary)
                        .matchedGeometryEffect(id: "selectedPill", in: pillNamespace)
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    selection = option
                }
            }
    }
}
