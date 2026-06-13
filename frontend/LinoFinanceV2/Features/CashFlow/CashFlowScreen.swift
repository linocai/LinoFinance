import SwiftUI

#if os(macOS)

// CashFlowScreen — STUB. Replaced by the P3 builder with the real D4 现金流 screen.
// Contract: `init(model: AppModel)`; real impl owns its own @StateObject view-model.
struct CashFlowScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("现金流").font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
            Text("P3 施工中").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
