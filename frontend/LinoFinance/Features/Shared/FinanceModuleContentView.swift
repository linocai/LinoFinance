import SwiftUI

struct FinanceModuleContentView: View {
    @Bindable var environment: AppEnvironment
    var module: FinanceModule?

    private var resolvedModule: FinanceModule {
        module ?? environment.selectedModule
    }

    var body: some View {
        switch resolvedModule {
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
