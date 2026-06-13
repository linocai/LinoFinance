import SwiftUI

#if os(macOS)

// AccountsScreen — STUB. Replaced by the P3 builder with the real D2 账户 screen.
// Contract: `init(model: AppModel)`; the real impl owns its own @StateObject
// feature view-model built on `model.apiClient` / `model.repository`, and presents
// the (P4-owned) ReconciliationScreen as the 对账 entry point.
struct AccountsScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("账户").font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
            Text("P3 施工中").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
