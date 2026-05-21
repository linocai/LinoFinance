#if os(macOS)
import SwiftUI

/// macOS sidebar 自定义行。选中态用 `Brand.primary → Brand.deep` 135° 渐变 + brand 调色阴影。
/// hover 走 `Surface.glass`。badge pill 跟随状态变色。
struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var badge: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13.5, weight: isActive ? .semibold : .medium))
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .foregroundStyle(isActive ? Color.white : FinanceTokens.Text.secondary)
                        .background(
                            Capsule().fill(
                                isActive
                                    ? Color.white.opacity(0.22)
                                    : FinanceTokens.Surface.glass
                            )
                        )
                        .overlay {
                            Capsule().stroke(
                                isActive ? Color.white.opacity(0.32) : FinanceTokens.Stroke.hairline,
                                lineWidth: 0.5
                            )
                        }
                }
            }
            .foregroundStyle(isActive ? Color.white : FinanceTokens.Text.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        if isActive {
            shape
                .fill(
                    LinearGradient(
                        colors: [FinanceTokens.Brand.primary, FinanceTokens.Brand.deep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .elevation(.tinted(FinanceTokens.Brand.primary, intensity: 0.35, radius: 14, y: 8))
        } else if isHovering {
            shape.fill(FinanceTokens.Surface.glass)
        } else {
            shape.fill(Color.clear)
        }
    }
}
#endif
