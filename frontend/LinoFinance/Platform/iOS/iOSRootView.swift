#if os(iOS)
import CoreSpotlight
import SwiftUI

struct iOSRootView: View {
    @Bindable var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: iOSTab = .dashboard
    @State private var morePath: [FinanceModule] = []
    @State private var isShowingQuickEntry = false
    @State private var quickEntryIntent: QuickEntryIntent = .expense

    var body: some View {
        Group {
            if requiresConnectionSetup {
                connectionSetupStack
            } else {
                mainTabs
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(environment.appearance.colorScheme)
        .tint(FinanceTokens.Brand.primary)
        .background(FinanceTokens.Surface.base.ignoresSafeArea())
        .privacyActivityMonitor(environment: environment)
        .onChange(of: requiresConnectionSetup) { _, needsSetup in
            if needsSetup {
                selectedTab = .more
                morePath = [.settings]
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await environment.authenticatePrivacyIfNeeded() }
            case .inactive, .background:
                environment.lockPrivacyForBackgroundIfNeeded()
            @unknown default:
                break
            }
        }
        .task {
            if requiresConnectionSetup {
                selectedTab = .more
                morePath = [.settings]
                try? await environment.settingsViewModel.refresh()
            } else {
                await environment.refreshPrimaryData()
            }
            await environment.authenticatePrivacyIfNeeded()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            Task {
                await environment.handleSpotlightUserActivity(activity)
                syncTabWithEnvironment()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .linoDidRegisterForRemoteNotifications)) { notification in
            guard let token = notification.userInfo?["token"] as? String else { return }
            Task {
                await environment.pushNotificationViewModel.register(apnsToken: token)
                environment.systemPushEnabled = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .linoDidFailRemoteNotificationRegistration)) { notification in
            let message = notification.userInfo?["message"] as? String ?? "APNs 注册失败"
            environment.pushNotificationViewModel.markFailure(message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .linoDidReceivePushTarget)) { notification in
            let targetType = notification.userInfo?["target_type"] as? String
            let targetID = notification.userInfo?["target_id"] as? String
            Task {
                await environment.handlePushNotificationTarget(type: targetType, id: targetID)
                syncTabWithEnvironment()
            }
        }
    }

    private var mainTabs: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                moduleStack(.dashboard)
                    .tabItem { Label("总览", systemImage: FinanceModule.dashboard.symbolName) }
                    .tag(iOSTab.dashboard)

                moduleStack(.entries)
                    .tabItem { Label("记账", systemImage: FinanceModule.entries.symbolName) }
                    .tag(iOSTab.entries)

                moduleStack(.cashFlow)
                    .tabItem { Label("现金流", systemImage: FinanceModule.cashFlow.symbolName) }
                    .tag(iOSTab.cashFlow)

                moduleStack(.credit)
                    .tabItem { Label("信用", systemImage: FinanceModule.credit.symbolName) }
                    .tag(iOSTab.credit)

                moreStack
                    .tabItem { Label("更多", systemImage: "ellipsis.circle.fill") }
                    .tag(iOSTab.more)
            }
            .toolbar(.hidden, for: .tabBar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FinanceTokens.Surface.base.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar(
                selection: $selectedTab,
                quickEntry: openQuickEntry,
                reimbursement: environment.beginNewReimbursement
            )
        }
        .sheet(item: detailSelection) { selection in
            NavigationStack {
                ScrollView {
                    SelectionDetailView(selection: selection, environment: environment)
                        .padding(20)
                }
                .navigationTitle("详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            environment.inspectorSelection = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingQuickEntry) {
            QuickEntrySheet(environment: environment, initialIntent: quickEntryIntent)
                .presentationDetents([.large])
        }
        .modifier(NewObjectSheets(environment: environment))
    }

    private var connectionSetupStack: some View {
        NavigationStack {
            SettingsView(environment: environment)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FinanceTokens.Surface.base.ignoresSafeArea())
    }

    private var requiresConnectionSetup: Bool {
        !environment.isAPITokenConfigured
            || isAuthError(environment.lastErrorMessage)
            || isAuthError(environment.dashboardViewModel.errorMessage)
            || isAuthError(environment.reportsViewModel.errorMessage)
            || isAuthError(environment.aiViewModel.errorMessage)
            || isAuthError(environment.settingsViewModel.errorMessage)
    }

    private func isAuthError(_ message: String?) -> Bool {
        guard let message else { return false }
        return message.contains("API 401") || message.localizedCaseInsensitiveContains("invalid API token")
    }

    private func openQuickEntry(_ intent: QuickEntryIntent) {
        quickEntryIntent = intent
        isShowingQuickEntry = true
    }

    private func syncTabWithEnvironment() {
        switch environment.selectedModule {
        case .dashboard:
            selectedTab = .dashboard
        case .entries:
            selectedTab = .entries
        case .cashFlow:
            selectedTab = .cashFlow
        case .credit:
            selectedTab = .credit
        case .accounts, .reconciliation, .reimbursements, .reports, .ai, .aiMemo, .notifications, .settings:
            selectedTab = .more
            morePath = [environment.selectedModule]
        }
    }

    private var detailSelection: Binding<InspectorSelection?> {
        Binding(
            get: { environment.inspectorSelection },
            set: { environment.inspectorSelection = $0 }
        )
    }

    private var moreStack: some View {
        NavigationStack(path: $morePath) {
            List {
                Section("模块") {
                    ForEach([FinanceModule.accounts, .reconciliation, .reimbursements, .reports, .ai, .aiMemo, .notifications, .settings]) { module in
                        NavigationLink(value: module) {
                            Label(module.title, systemImage: module.symbolName)
                        }
                    }
                }

                Section("连接") {
                    ConnectionStatusView(environment: environment)
                }
            }
            .navigationTitle("更多")
            .navigationDestination(for: FinanceModule.self) { module in
                FinanceModuleContentView(environment: environment, module: module)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarItems(for: module) }
                    .toolbarBackground(FinanceTokens.Surface.raised, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .onAppear {
                        environment.selectedModule = module
                    }
            }
        }
        .onAppear {
            environment.selectedModule = .settings
        }
    }

    private func moduleStack(_ module: FinanceModule) -> some View {
        NavigationStack {
            FinanceModuleContentView(environment: environment, module: module)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems(for: module) }
                .toolbarBackground(FinanceTokens.Surface.raised, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            environment.selectedModule = module
        }
    }

    @ToolbarContentBuilder
    private func toolbarItems(for module: FinanceModule) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            newActionMenu(for: module)
            Button {
                Task { await environment.refreshCurrentModule() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("刷新")
        }
    }

    @ViewBuilder
    private func newActionMenu(for module: FinanceModule) -> some View {
        switch module {
        case .dashboard, .entries:
            Button {
                environment.beginNewEntry()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建记录")
        case .accounts:
            Button {
                environment.beginNewAccount()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建账户")
        case .cashFlow:
            Button {
                environment.beginNewCashFlow()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建现金流")
        case .reimbursements:
            Button {
                environment.beginNewReimbursement()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建报销")
        case .credit:
            Menu {
                Button("信用消费 / 还款") { environment.beginNewEntry() }
                Button("新建账单周期") { environment.isShowingNewStatementCycleSheet = true }
                Button("新建分期") { environment.isShowingNewInstallmentSheet = true }
                Button("新建订阅") { environment.isShowingNewSubscriptionSheet = true }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建信用对象")
        case .notifications:
            Button {
                environment.isShowingNewNotificationSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建通知")
        case .reports, .ai, .aiMemo, .reconciliation, .settings:
            EmptyView()
        }
    }
}

enum iOSTab: Hashable {
    case dashboard
    case entries
    case cashFlow
    case credit
    case more
}

private struct ConnectionStatusView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(environment.lastErrorMessage == nil && environment.isAPITokenConfigured ? FinanceTokens.State.income : FinanceTokens.State.warning)
                    .frame(width: 8, height: 8)
                Text(environment.isAPITokenConfigured ? "API 已配置" : "需要配置 Token")
                    .font(.subheadline.weight(.semibold))
            }
            Text(environment.apiClient.baseURL.absoluteString)
                .font(.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
                .textSelection(.enabled)
            if let message = environment.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(FinanceTokens.State.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NewObjectSheets: ViewModifier {
    @Bindable var environment: AppEnvironment

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $environment.isShowingNewAccountSheet) {
                NavigationStack { NewAccountSheet(environment: environment) }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $environment.isShowingNewEntrySheet) {
                NavigationStack { NewEntrySheet(environment: environment) }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $environment.isShowingNewCashFlowSheet) {
                NavigationStack { NewCashFlowSheet(environment: environment) }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $environment.isShowingNewReimbursementSheet) {
                NavigationStack { NewReimbursementClaimSheet(environment: environment) }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $environment.isShowingNewStatementCycleSheet) {
                NavigationStack { NewStatementCycleSheet(environment: environment) }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $environment.isShowingNewInstallmentSheet) {
                NavigationStack { NewInstallmentPlanSheet(environment: environment) }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $environment.isShowingNewSubscriptionSheet) {
                NavigationStack { NewSubscriptionSheet(environment: environment) }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $environment.isShowingNewNotificationSheet) {
                NavigationStack { NewNotificationRuleSheet(environment: environment) }
                    .presentationDetents([.large])
            }
    }
}

#endif
