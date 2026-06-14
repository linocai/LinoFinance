import Foundation
import SwiftUI

// AppModel+Platform — Py platform-integration helpers.
//
// Derived values the MenuBarExtra popover + the widget snapshot writer need,
// plus the snapshot assembly itself, plus push-device registration and the
// Sign in with Apple / admin-token re-auth path. Split out of the lean P2
// `AppModel` so the platform-integration surface lives in one place.

@MainActor
extension AppModel {

    // MARK: - Derived metrics (menu bar + snapshot)

    /// "未来一月可支配" CNY — the dashboard's per-currency disposable, CNY row.
    var disposable30dCny: DecimalValue {
        let rows = dashboard?.disposable30dByCurrency ?? []
        return rows.first(where: { $0.currency == .cny })?.amount ?? DecimalValue(0)
    }

    /// Sum of all active USD balance accounts' current balance (mainly USDT today).
    var usdBalanceTotal: DecimalValue {
        let sum = accounts
            .filter { $0.type == .balance && $0.currency == .usd }
            .map { $0.currentBalance.value }
            .reduce(Decimal(0), +)
        return DecimalValue(sum)
    }

    /// 30-day net cash flow (CNY) — from the dashboard's cashFlow30d rows.
    var cashFlow30dCny: DecimalValue {
        let rows = dashboard?.cashFlow30dByCurrency ?? []
        return rows.first(where: { $0.currency == .cny })?.amount ?? DecimalValue(0)
    }

    /// Next unpaid/unclosed credit cycle, soonest due first.
    var nextCreditCycle: CreditStatementCycleDTO? {
        cycles
            .filter { $0.status != "paid" && $0.status != "closed" }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    /// AI plans awaiting the user's attention.
    var pendingAIPlans: [AIPlanDTO] {
        aiPlans.filter {
            ["requires_confirmation", "auto_confirm_candidate", "failed"].contains($0.status)
        }
    }

    // MARK: - Widget snapshot

    /// Assemble a `V2WidgetSnapshot` from the cached DTOs and push it to the
    /// shared App Group. Called at the tail of `refreshAll()`.
    func writeWidgetSnapshot() {
        guard let summary = dashboard else { return }

        let nextDue = nextCreditCycle.map { cycle in
            V2WidgetSnapshot.CreditDue(
                accountName: accounts.first { $0.id == cycle.creditAccountId }?.name ?? "信用账户",
                dueDate: cycle.dueDate,
                amount: FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency)
            )
        }

        let snapshot = V2WidgetSnapshot(
            netWorth: FinanceFormatter.money(summary.netWorthCny),
            balance: FinanceFormatter.money(summary.balanceTotalCny),
            creditLiability: FinanceFormatter.money(summary.creditLiabilityTotalCny),
            thirtyDayNet: FinanceFormatter.money(cashFlow30dCny),
            trend: [],
            nextCreditDue: nextDue,
            pendingAIPlanCount: pendingAIPlans.count,
            updatedAt: Date()
        )
        V2WidgetSnapshotStore.shared.write(snapshot)
    }

    // MARK: - Push device registration (Py ③)

    /// Register the APNs token with the backend. (A) wires the call; the real
    /// token only arrives on a real device (留 (B)).
    func registerPushDevice(apnsToken: String) async {
        let request = PushDeviceRegisterRequest(
            deviceId: Self.pushDeviceID(),
            platform: Self.currentPlatform,
            apnsToken: apnsToken,
            appVersion: Self.currentAppVersion
        )
        _ = try? await repository.registerPushDevice(request)
    }

    private static func pushDeviceID() -> String {
        let key = "linofinance.push.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        #if os(iOS)
        let generated = UUID().uuidString
        #else
        let generated = Host.current().localizedName ?? UUID().uuidString
        #endif
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    // MARK: - Auth (Py ②)

    static var currentPlatform: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Exchange an Apple identity_token for a session token, persist it to the
    /// session keychain slot, rebuild the clients around it, then refresh. The
    /// admin-token bypass stays valid in parallel (`readEffectiveToken` prefers
    /// the session slot once present).
    func signInWithApple(
        identityToken: String,
        firstName: String?,
        lastName: String?,
        deviceLabel: String
    ) async throws {
        let request = AppleSignInRequest(
            identityToken: identityToken,
            deviceLabel: deviceLabel,
            platform: Self.currentPlatform,
            appVersion: Self.currentAppVersion,
            firstName: firstName,
            lastName: lastName
        )
        let response = try await apiClient.signInWithApple(request)
        try SecureTokenStore.shared.saveToken(response.sessionToken, kind: .session)
        rebuildClients(token: response.sessionToken)
        await refreshAll()
    }

    /// Save a manually-entered admin token (dev / ops escape hatch) and rebuild.
    func saveAdminToken(_ token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try SecureTokenStore.shared.saveToken(trimmed, kind: .admin)
        rebuildClients(token: SecureTokenStore.shared.readEffectiveToken())
        await refreshAll()
    }
}
