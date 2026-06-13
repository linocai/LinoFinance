import SwiftUI

#if os(macOS)

// ReconciliationScreen — STUB. Replaced by the P4 builder with the real D9 对账 screen.
// Not a sidebar destination — presented FROM AccountsScreen (P3) since 对账 is how
// account balances change. Contract: `init(model: AppModel)`; presentable as a sheet.
struct ReconciliationScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("对账").font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
            Text("P4 施工中").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
    }
}

#endif
