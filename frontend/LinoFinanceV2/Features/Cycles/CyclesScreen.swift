import SwiftUI

#if os(macOS)

// CyclesScreen — STUB. Replaced by the P4 builder with the real D7 周期 screen
// (订阅 + 分期 + 信用账单周期). Contract: `init(model: AppModel)`.
struct CyclesScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("周期").font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
            Text("P4 施工中").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
