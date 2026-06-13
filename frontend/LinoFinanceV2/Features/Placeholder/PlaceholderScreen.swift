import SwiftUI

// PlaceholderScreen — sidebar destinations not yet implemented in P2.
//
// Overview ships real in P2; 账户 / 现金流 / 流水 / 报销 / 周期 / 报表 / 设置 land in
// P3–P5. Until then their sidebar selection shows a glass placeholder so the shell
// (floating sidebar + bloom + glass) stays navigable and visually complete.

struct PlaceholderScreen: View {
    let destination: SidebarDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text(destination.title)
                    .font(Theme.Font.pageTitle())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("即将到来")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: destination.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.Color.brandEnd)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(destination.title)页面")
                            .font(Theme.Font.subtitle(.semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("此页将在后续 Phase 接入真实数据。")
                            .font(Theme.Font.caption())
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                }
            }
        }
    }
}
