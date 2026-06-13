import SwiftUI

// GlassMenuPicker — a glass dropdown field that replaces the native popup
// `Picker(.menu)` / `Picker` button (which reads as old-iOS). Shows the current
// selection label + a chevron inside a glass field; tapping opens a native Menu
// whose items the caller supplies (one Button per option). Matches the comp's
// clean, minimal select fields.
//
// Usage:
//   GlassMenuPicker(label: account?.name ?? "未选择", isPlaceholder: account == nil) {
//       ForEach(accounts) { a in Button(a.name) { selection = a.id } }
//   }
struct GlassMenuPicker<MenuContent: View>: View {
    /// The current selection's display text (or a placeholder string).
    let label: String
    /// Render the label in the muted placeholder color (nothing chosen yet).
    var isPlaceholder: Bool = false
    var disabled: Bool = false
    @ViewBuilder var menu: () -> MenuContent

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(Theme.Font.body())
                    .foregroundStyle(isPlaceholder ? Theme.Color.textTertiary : Theme.Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                shape.fill(Theme.Color.glassFill)
                    .overlay(shape.strokeBorder(Theme.Color.glassStroke, lineWidth: 0.5))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
