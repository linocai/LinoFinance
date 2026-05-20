#if os(iOS)
import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct LinoCreditDueAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let dueDate: Date
        let remainingAmount: String
        let statusText: String
    }

    let cycleID: String
    let accountName: String
}

struct LinoAIPlanAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let statusText: String
        let actionCount: Int
    }

    let planID: String
    let sourceText: String
}
#endif

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    func startCreditDue(cycle: CreditStatementCycleDTO, accountName: String, reminderDays: Int) {
#if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = LinoCreditDueAttributes(cycleID: cycle.id, accountName: accountName)
        let state = LinoCreditDueAttributes.ContentState(
            dueDate: cycle.dueDate,
            remainingAmount: FinanceFormatter.money(cycle.remainingAmount, currency: cycle.currency),
            statusText: "\(max(Calendar.current.dateComponents([.day], from: Date(), to: cycle.dueDate).day ?? reminderDays, 0)) 天后到期"
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: cycle.dueDate),
                pushType: nil
            )
        } catch {
            // Live Activity is best-effort; failures should never block credit workflows.
        }
#endif
    }

    func startAIPlan(plan: AIPlanDTO) {
#if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = LinoAIPlanAttributes(planID: plan.id, sourceText: plan.sourceText)
        let state = LinoAIPlanAttributes.ContentState(
            statusText: plan.status.financeStatusTitle,
            actionCount: plan.actions.count
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60)),
                pushType: nil
            )
        } catch {
            // Dynamic Island hints are optional and local-only in P4.
        }
#endif
    }
}
#endif
