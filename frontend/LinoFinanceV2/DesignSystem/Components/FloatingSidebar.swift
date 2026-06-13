import SwiftUI

#if os(macOS)

// FloatingSidebar — the macOS soul control (HANDOFF §2.6, plan §E).
//
// A FLOATING rounded glass card, NOT a traditional flush split-view sidebar:
//   • 14pt from the window's left edge, vertically centered, 200pt wide,
//   • height WRAPS its content (does not stretch to window height),
//   • strong `.glassEffect` + heavy soft shadow so it visibly floats,
//   • content top→bottom: "浏览" caption → 8 nav rows (selected row = soft
//     highlight bar) → indigo/violet "记一笔" button → account avatar chip.
//
// Self-drawn — NavigationSplitView cannot produce the floating/centered/compact
// look (HANDOFF §2.6 explicitly says build it by hand).

struct FloatingSidebar: View {
    @Binding var selection: SidebarDestination
    var onAddEntry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("浏览")
                .font(Theme.Font.caption(.semibold))
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.leading, 8)
                .padding(.bottom, 8)

            VStack(spacing: 2) {
                ForEach(SidebarDestination.allCases) { dest in
                    SidebarRow(
                        destination: dest,
                        isSelected: selection == dest
                    ) { selection = dest }
                }
            }

            PrimaryActionButton(title: "记一笔", compact: true, action: onAddEntry)
                .padding(.top, 14)

            Divider()
                .overlay(Theme.Color.divider)
                .padding(.vertical, 12)

            accountChip
        }
        .padding(14)
        .frame(width: 200)
        .glassPanel(
            cornerRadius: Theme.Radius.sidebar,
            shadow: Theme.Shadow.sidebar
        )
    }

    private var accountChip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Theme.Color.brandGradient)
                .frame(width: 30, height: 30)
                .overlay {
                    Text("L")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("Lino")
                    .font(Theme.Font.body(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("已通过 Apple 登录")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SidebarRow: View {
    let destination: SidebarDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Theme.Color.brandEnd : Theme.Color.textSecondary)
                Text(destination.title)
                    .font(Theme.Font.body(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowFill)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var rowFill: Color {
        if isSelected {
            return Theme.Color.brandSoft
        } else if hovering {
            return Theme.Color.textPrimary.opacity(0.05)
        }
        return .clear
    }
}

#endif
