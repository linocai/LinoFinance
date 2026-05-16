import SwiftUI

struct MacRootView: View {
    @Bindable var environment: AppEnvironment
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(environment: environment)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } content: {
            ModuleContentView(environment: environment)
                .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        } detail: {
            InspectorView(environment: environment)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    environment.beginNewEntry()
                } label: {
                    Label("新建", systemImage: "plus")
                }

                Button {
                    environment.beginAI()
                } label: {
                    Label("AI 对话", systemImage: "sparkles")
                }

                Picker("币种", selection: $environment.displayCurrency) {
                    ForEach(CurrencyCode.allCases, id: \.self) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .pickerStyle(.menu)

                Picker("时间范围", selection: $environment.dateRange) {
                    ForEach(DateRangeChoice.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.menu)

                TextField("搜索", text: $environment.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .focused($isSearchFocused)

                Button {
                    Task { await environment.refreshCurrentModule() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
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
    }
}

private struct SidebarView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        List(selection: $environment.selectedModule) {
            Section {
                ForEach([MacModule.dashboard, .accounts, .entries, .cashFlow, .reimbursements, .credit, .reports, .ai]) { module in
                    Label(module.title, systemImage: module.symbolName)
                        .tag(module)
                }
            }

            Section {
                Label(MacModule.notifications.title, systemImage: MacModule.notifications.symbolName)
                    .tag(MacModule.notifications)
                Label(MacModule.settings.title, systemImage: MacModule.settings.symbolName)
                    .tag(MacModule.settings)
            }
        }
        .navigationTitle("LinoFinance")
        .safeAreaInset(edge: .bottom) {
            ConnectionFooter(environment: environment)
                .padding(12)
        }
    }
}

private struct ConnectionFooter: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(environment.lastErrorMessage == nil ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(environment.lastErrorMessage == nil ? "本地 API 已连接" : "离线 / 待连接")
                    .font(.caption.weight(.semibold))
            }
            Text(environment.apiClient.baseURL.absoluteString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let message = environment.lastErrorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModuleContentView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        switch environment.selectedModule {
        case .dashboard:
            DashboardView(environment: environment)
        case .accounts:
            AccountsView(environment: environment)
        case .entries:
            EntriesView(environment: environment)
        case .cashFlow:
            CashFlowView(environment: environment)
        case .reimbursements:
            ReimbursementsView(environment: environment)
        case .credit:
            CreditView(environment: environment)
        case .reports:
            ReportsView(environment: environment)
        case .ai:
            AIWorkspaceView(environment: environment)
        case .notifications:
            NotificationsView(environment: environment)
        case .settings:
            SettingsView(environment: environment)
        }
    }
}
