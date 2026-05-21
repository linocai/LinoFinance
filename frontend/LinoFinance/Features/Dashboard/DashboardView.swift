import SwiftUI

/// 平台 router —— macOS 走 MacDashboardView，iOS 走 iOSDashboardView。
/// 老的 DashboardHero / SummaryGrid / DashboardCashFlowCard 等私有 struct 已删；
/// 视觉版式以 HTML B / C 两节为权威。
struct DashboardView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
#if os(macOS)
        MacDashboardView(environment: environment)
#else
        iOSDashboardView(environment: environment)
#endif
    }
}
