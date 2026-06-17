import Foundation
import SwiftUI

#if os(macOS)

// CyclesModel — D7 周期 view-model (订阅 + 分期 + 信用账单周期).
//
// Three independent resources, loaded together:
//   • 订阅 SubscriptionRuleDTO   — list/create + pause/resume/generate-next/cancel
//   • 分期 InstallmentPlanDTO     — list/create + early-paid-off/paid-off/cancel
//   • 信用账单周期 CreditStatementCycleDTO — list(creditAccountID)/create
//        (read + create only — NO update/close, per plan §D7 + backlog)
@MainActor
final class CyclesModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var subscriptions: [SubscriptionRuleDTO] = []
    @Published private(set) var installments: [InstallmentPlanDTO] = []
    @Published private(set) var statementCycles: [CreditStatementCycleDTO] = []
    @Published private(set) var state: LoadState = .idle

    private let apiClient: LinoAPIClient

    init(apiClient: LinoAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Load

    func load() async {
        state = .loading
        do {
            async let subs = apiClient.listSubscriptionRules()
            async let plans = apiClient.listInstallmentPlans()
            async let cycles = apiClient.listStatementCycles()
            subscriptions = try await subs
            installments = try await plans
            statementCycles = try await cycles
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Subscriptions

    func pauseSubscription(_ id: String) async throws {
        _ = try await apiClient.pauseSubscriptionRule(id)
        subscriptions = (try? await apiClient.listSubscriptionRules()) ?? subscriptions
    }

    func resumeSubscription(_ id: String) async throws {
        _ = try await apiClient.resumeSubscriptionRule(id)
        subscriptions = (try? await apiClient.listSubscriptionRules()) ?? subscriptions
    }

    func generateNextSubscription(_ id: String) async throws {
        _ = try await apiClient.generateNextSubscriptionCashFlow(id)
        subscriptions = (try? await apiClient.listSubscriptionRules()) ?? subscriptions
    }

    func cancelSubscription(_ id: String) async throws {
        _ = try await apiClient.cancelSubscriptionRule(id)
        subscriptions = (try? await apiClient.listSubscriptionRules()) ?? subscriptions
    }

    @discardableResult
    func createSubscription(_ request: SubscriptionRuleCreateRequest) async throws -> SubscriptionRuleDTO {
        let rule = try await apiClient.createSubscriptionRule(request)
        subscriptions = (try? await apiClient.listSubscriptionRules()) ?? subscriptions
        return rule
    }

    // MARK: - Installments

    func markInstallmentEarlyPaidOff(_ id: String) async throws {
        _ = try await apiClient.markInstallmentEarlyPaidOff(id)
        installments = (try? await apiClient.listInstallmentPlans()) ?? installments
    }

    func markInstallmentPaidOff(_ id: String) async throws {
        _ = try await apiClient.markInstallmentPaidOff(id)
        installments = (try? await apiClient.listInstallmentPlans()) ?? installments
    }

    func cancelInstallment(_ id: String) async throws {
        _ = try await apiClient.cancelInstallmentPlan(id)
        installments = (try? await apiClient.listInstallmentPlans()) ?? installments
    }

    @discardableResult
    func createInstallment(_ request: InstallmentPlanCreateRequest) async throws -> InstallmentPlanDTO {
        let plan = try await apiClient.createInstallmentPlan(request)
        installments = (try? await apiClient.listInstallmentPlans()) ?? installments
        return plan
    }

    // MARK: - Statement cycles (read + create + correct, v2.3.0 P1/P2)

    @discardableResult
    func createStatementCycle(_ request: CreditStatementCycleCreateRequest) async throws -> CreditStatementCycleDTO {
        let cycle = try await apiClient.createStatementCycle(request)
        statementCycles = (try? await apiClient.listStatementCycles()) ?? statementCycles
        return cycle
    }

    @discardableResult
    func updateStatementCycle(_ id: String, request: CreditStatementCycleUpdateRequest) async throws -> CreditStatementCycleDTO {
        let cycle = try await apiClient.updateStatementCycle(id, request: request)
        statementCycles = (try? await apiClient.listStatementCycles()) ?? statementCycles
        return cycle
    }

    func markStatementCyclePaid(_ id: String) async throws {
        _ = try await apiClient.markStatementCyclePaid(id)
        statementCycles = (try? await apiClient.listStatementCycles()) ?? statementCycles
    }

    func voidStatementCycle(_ id: String) async throws {
        _ = try await apiClient.voidStatementCycle(id)
        statementCycles = (try? await apiClient.listStatementCycles()) ?? statementCycles
    }
}

#endif
