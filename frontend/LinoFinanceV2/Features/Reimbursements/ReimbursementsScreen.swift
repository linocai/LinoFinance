import SwiftUI

#if os(macOS)

// ReimbursementsScreen — STUB. Replaced by the P4 builder with the real D6 报销 screen.
// Contract: `init(model: AppModel)`; real impl owns its own @StateObject view-model.
struct ReimbursementsScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("报销").font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
            Text("P4 施工中").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
