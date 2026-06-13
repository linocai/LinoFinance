import SwiftUI

// PrimaryDarkButton — in-page primary action (保存 / 提交 / 兑现), R0 Phase A.
//
// Comp source: lf_save.png — a near-black filled, wide, ~14-radius button with
// white label. User-decided主按钮风格: pure dark fill, dark-mode reversed —
// fill = `Theme.Color.textPrimary` (light #1C1C1E / dark #F5F5F7), text = its
// reverse `Theme.Color.inkButtonText` (light #FFFFFF / dark #1C1C1E).
//
// The indigo→violet brand gradient stays reserved for the single sidebar 记一笔
// button (`PrimaryActionButton`) — this is the neutral in-page CTA.

struct PrimaryDarkButton: View {
    var title: String
    var systemImage: String?
    /// Stretch to fill the available width (form footers).
    var fullWidth: Bool = false
    var isLoading: Bool = false
    var action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        fullWidth: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.fullWidth = fullWidth
        self.isLoading = isLoading
        self.action = action
    }

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Color.inkButtonText)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.Color.inkButtonText)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 13)
            .padding(.horizontal, fullWidth ? 16 : 24)
            .background(
                Theme.Color.textPrimary,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .scaleEffect(pressed ? 0.98 : 1)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { p in
            withAnimation(.easeOut(duration: 0.1)) { pressed = p }
        }, perform: {})
    }
}

// SubtleTextButton — the soft 取消 partner to PrimaryDarkButton.
//
// Comp source: lf_save.png — light gray filled, low-contrast secondary action that
// sits next to the dark primary. Faint `textSecondary` fill + `textPrimary` label.

struct SubtleTextButton: View {
    var title: String
    var fullWidth: Bool = false
    var action: () -> Void

    init(_ title: String, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.fullWidth = fullWidth
        self.action = action
    }

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, 13)
                .padding(.horizontal, 22)
                .background(
                    Theme.Color.textSecondary.opacity(hovering ? 0.16 : 0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
    }
}
