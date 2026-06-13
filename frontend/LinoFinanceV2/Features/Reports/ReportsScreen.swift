import SwiftUI

#if os(macOS)

// ReportsScreen — STUB. Replaced by the P4 builder with the real D8 报表 screen
// (6 张 Swift Charts). Contract: `init(model: AppModel)`.
struct ReportsScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("报表").font(Theme.Font.pageTitle()).foregroundStyle(Theme.Color.textPrimary)
            Text("P4 施工中").font(Theme.Font.caption()).foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
