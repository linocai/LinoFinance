#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @Bindable var environment: AppEnvironment
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(environment: environment)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } content: {
            FinanceModuleContentView(environment: environment)
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
        .preferredColorScheme(environment.appearance.colorScheme)
        .tint(FinanceTokens.Brand.primary)
        .background(FinanceTokens.Surface.base)
    }
}

private struct SidebarView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        List(selection: $environment.selectedModule) {
            Section {
                ForEach([FinanceModule.dashboard, .accounts, .entries, .cashFlow, .reimbursements, .credit, .reports, .ai]) { module in
                    Label(module.title, systemImage: module.symbolName)
                        .tag(module)
                }
            }

            Section {
                Label(FinanceModule.notifications.title, systemImage: FinanceModule.notifications.symbolName)
                    .tag(FinanceModule.notifications)
                Label(FinanceModule.settings.title, systemImage: FinanceModule.settings.symbolName)
                    .tag(FinanceModule.settings)
            }
        }
        .navigationTitle("LinoF")
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
                    .fill(environment.lastErrorMessage == nil ? FinanceTokens.State.income : FinanceTokens.State.warning)
                    .frame(width: 8, height: 8)
                Text(environment.lastErrorMessage == nil ? "API 已连接" : "离线 / 待连接")
                    .font(.caption.weight(.semibold))
            }
            Text(environment.apiClient.baseURL.absoluteString)
                .font(.caption2)
                .foregroundStyle(FinanceTokens.Text.secondary)
                .textSelection(.enabled)
            if let message = environment.lastErrorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(FinanceTokens.State.warning)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
