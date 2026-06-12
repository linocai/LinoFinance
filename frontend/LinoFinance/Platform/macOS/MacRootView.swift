#if os(macOS)
import AppKit
import CoreSpotlight
import SwiftUI

struct MacRootView: View {
    @Bindable var environment: AppEnvironment
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        Group {
            if environment.isResolvingAuth {
                ProgressView("正在加载…")
                    .frame(minWidth: 1180, minHeight: 760)
                    .background(CanvasBackground())
            } else if environment.needsSignIn {
                SignInWithAppleView(environment: environment)
                    .frame(minWidth: 1180, minHeight: 760)
            } else {
                mainLayout
            }
        }
        .task {
            await environment.loadCurrentUser()
            if !environment.needsSignIn {
                await environment.refreshSessions()
            }
        }
    }

    private var mainLayout: some View {
        NavigationSplitView {
            SidebarView(environment: environment)
                .navigationSplitViewColumnWidth(min: 220, ideal: 230)
        } content: {
            FinanceModuleContentView(environment: environment)
                .navigationSplitViewColumnWidth(min: 600, ideal: 820)
        } detail: {
            InspectorView(environment: environment)
                .navigationSplitViewColumnWidth(min: 300, ideal: 320)
        }
        // 工具栏 5 按钮（币种 / 区间 / 快速记账 / ＋记一笔 / AI）已删（v1.4.0 P4）。
        // 入口收敛到：sidebar 底部大加号、⌘N/⌘⇧N、菜单「窗口→快速记账」、
        // MenuBarExtra、AI 菜单 ⌘⇧A。DEBUG showcase 迁入 LinoFinanceApp 的
        // #if DEBUG CommandMenu，经 environment.isShowingDesignShowcase 触发。
#if DEBUG
        .sheet(isPresented: $environment.isShowingDesignShowcase) {
            NavigationStack {
                DesignSystemShowcaseView()
            }
            .frame(minWidth: 720, minHeight: 640)
        }
#endif
        .sheet(isPresented: $environment.isShowingNewAccountSheet) {
            NewAccountSheet(environment: environment)
                .frame(width: 420)
        }
        .sheet(isPresented: $environment.isShowingNewEntrySheet) {
            NewEntrySheet(environment: environment)
                .frame(width: 520)
        }
        .sheet(isPresented: $environment.isShowingNewCashFlowSheet) {
            NewCashFlowSheet(environment: environment)
                .frame(width: 520)
        }
        .sheet(isPresented: $environment.isShowingEditCashFlowSheet) {
            if let item = environment.editingCashFlowItem {
                EditCashFlowSheet(environment: environment, item: item)
                    .frame(width: 520)
            }
        }
        .sheet(isPresented: $environment.isShowingSettleCashFlowSheet) {
            if let item = environment.settlingCashFlowItem {
                SettleCompletionSheet(environment: environment, item: item)
                    .frame(width: 460)
            }
        }
        .sheet(isPresented: $environment.isShowingNewReimbursementSheet) {
            NewReimbursementClaimSheet(environment: environment)
                .frame(width: 540)
        }
        .sheet(isPresented: $environment.isShowingNewStatementCycleSheet) {
            NewStatementCycleSheet(environment: environment)
                .frame(width: 520)
        }
        .sheet(isPresented: $environment.isShowingNewInstallmentSheet) {
            NewInstallmentPlanSheet(environment: environment)
                .frame(width: 540)
        }
        .sheet(isPresented: $environment.isShowingNewSubscriptionSheet) {
            NewSubscriptionSheet(environment: environment)
                .frame(width: 520)
        }
        .sheet(isPresented: $environment.isShowingNewNotificationSheet) {
            NewNotificationRuleSheet(environment: environment)
                .frame(width: 520)
        }
        .task {
            await environment.refreshPrimaryData()
            await environment.authenticatePrivacyIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            environment.lockPrivacyForBackgroundIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await environment.authenticatePrivacyIfNeeded() }
        }
        .onChange(of: environment.isSearchFocused) { _, focused in
            isSearchFocused = focused
        }
        .onChange(of: isSearchFocused) { _, focused in
            environment.isSearchFocused = focused
        }
        .onChange(of: environment.selectedModule) { _, module in
            environment.inspectorSelection = .module(module)
            Task { await environment.refreshCurrentModule() }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            Task { await environment.handleSpotlightUserActivity(activity) }
        }
        .preferredColorScheme(environment.appearance.colorScheme)
        .tint(FinanceTokens.Brand.primary)
        .background(CanvasBackground())
        .privacyActivityMonitor(environment: environment)
    }
}

private struct SidebarView: View {
    @Bindable var environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    // 对齐 HTML C 节 sidebar：两组 + 共 10 项。
    // 隐藏：reconciliation（入口在账户页）、aiMemo（入口在 AI 工作台）。
    private static let consoleModules: [FinanceModule] = [
        .dashboard, .accounts, .entries, .cashFlow, .credit, .reimbursements
    ]

    private static let analyticsModules: [FinanceModule] = [
        .reports, .ai, .notifications, .settings
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sidebarGroup(title: "主控台", modules: Self.consoleModules)
                sidebarGroup(title: "分析 · AI", modules: Self.analyticsModules)
                // 今日盈亏快录已迁入总览页投资卡（v1.4.0 P3）；sidebar 组移除。
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .scrollContentBackground(.hidden)
        .background(FinanceTokens.Surface.deepGlass)
        .navigationTitle("LinoFinance")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                // 主控台下部巨大加号——v1.4.0 P4 取代被删的 toolbar ＋ 按钮，
                // 作为新建记录的醒目主入口。
                Button {
                    environment.beginNewEntry()
                } label: {
                    Label("记一笔", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(FinanceTokens.Brand.primary)
                // ⌘N 由 LinoFinanceApp 的 CommandGroup(.newItem) 全局拥有，
                // 这里不再重复绑定，避免快捷键歧义；按钮纯作可见主入口。
                .help("记一笔 ⌘N")

                ConnectionFooter(environment: environment)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func sidebarGroup(title: String, modules: [FinanceModule]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(FinanceTypography.sectionKicker)
                .tracking(0.8)
                .foregroundStyle(FinanceTokens.Text.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            ForEach(modules) { module in
                SidebarRow(
                    title: module.title,
                    systemImage: module.symbolName,
                    isActive: environment.selectedModule == module,
                    action: { environment.selectedModule = module }
                )
                .contextMenu {
                    Button("在新窗口中打开") {
                        openWindow(id: "module", value: module)
                    }
                }
            }
        }
    }
}

private struct ConnectionFooter: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(environment.lastErrorMessage == nil ? FinanceTokens.State.income : FinanceTokens.State.warning)
                    .frame(width: 8, height: 8)
                Text(environment.lastErrorMessage == nil ? "API 已连接" : "离线 / 待连接")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FinanceTokens.Text.primary)
            }
            Text(environment.apiClient.baseURL.absoluteString)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(FinanceTokens.Text.secondary)
                .textSelection(.enabled)
            if let message = environment.lastErrorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(FinanceTokens.State.warning)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: FinanceTokens.Radius.md, strength: .regular, elevation: nil)
    }
}

#endif
