import Foundation

struct WidgetSnapshot: Codable, Equatable {
    struct CreditDue: Codable, Equatable {
        let accountName: String
        let dueDate: Date
        let amount: String
    }

    let netWorth: String
    let balance: String
    let creditLiability: String
    let thirtyDayNet: String
    let trend: [Double]
    let nextCreditDue: CreditDue?
    let pendingAIPlanCount: Int
    let updatedAt: Date
}

struct WidgetSnapshotStore {
    static let appGroupID = "group.com.lino.linofinance"
    static let snapshotKey = "linofinance.widget.snapshot"
    static let shared = WidgetSnapshotStore()

    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    func readSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder.linoWidget.decode(WidgetSnapshot.self, from: data)
    }

    @MainActor
    func writeSnapshot(from environment: AppEnvironment) {
        guard environment.widgetAutoUpdateEnabled else { return }
        guard let summary = environment.dashboardViewModel.summary else { return }

        let cashFlow = environment.reportsViewModel.bundle?.cashFlow
        let future30 = cashFlow?.windows.first { $0.days == 30 }?.netCny ?? DecimalValue(0)
        let trend = (cashFlow?.dailyNetCny ?? []).map {
            NSDecimalNumber(decimal: $0.netCny.value).doubleValue
        }
        let nextDue = environment.creditViewModel.cycles
            .filter { $0.status != "paid" && $0.status != "closed" }
            .sorted { $0.dueDate < $1.dueDate }
            .first
            .map { cycle in
                WidgetSnapshot.CreditDue(
                    accountName: environment.accountsViewModel.accounts.first { $0.id == cycle.creditAccountId }?.name ?? "信用账户",
                    dueDate: cycle.dueDate,
                    amount: FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency)
                )
            }
        let pendingAI = environment.aiViewModel.plans.filter {
            ["requires_confirmation", "auto_confirm_candidate", "failed"].contains($0.status)
        }.count
        let snapshot = WidgetSnapshot(
            netWorth: FinanceFormatter.money(summary.netWorthCny),
            balance: FinanceFormatter.money(summary.balanceTotalCny),
            creditLiability: FinanceFormatter.money(summary.creditLiabilityTotalCny),
            thirtyDayNet: FinanceFormatter.money(future30),
            trend: trend,
            nextCreditDue: nextDue,
            pendingAIPlanCount: pendingAI,
            updatedAt: Date()
        )

        if let data = try? JSONEncoder.linoWidget.encode(snapshot) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }
}

private extension JSONDecoder {
    static var linoWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var linoWidget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
