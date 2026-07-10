import Foundation
import SwiftUI

// AppModel+Platform — Py platform-integration helpers.
//
// Derived values the MenuBarExtra popover needs, plus push-device
// registration and the Sign in with Apple / admin-token re-auth path. Split
// out of the lean P2 `AppModel` so the platform-integration surface lives in
// one place.

@MainActor
extension AppModel {

    // MARK: - Derived metrics (menu bar)

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

    /// Real Apple-session logout: tell the backend, clear the session keychain
    /// slot, then rebuild around whatever remains (an admin token, or nil).
    func logoutSession() async throws {
        try await apiClient.logout()
        try? SecureTokenStore.shared.clear(kind: .session)
        rebuildClients(token: SecureTokenStore.shared.readEffectiveToken())
        await refreshAll()
    }

    /// Clear the local admin-token bypass. Admin tokens are an env/ops escape
    /// hatch the backend refuses to "log out" (400) — clearing them is purely a
    /// local keychain operation, no backend call.
    func clearAdminToken() async {
        try? SecureTokenStore.shared.clear(kind: .admin)
        rebuildClients(token: SecureTokenStore.shared.readEffectiveToken())
        await refreshAll()
    }
}
