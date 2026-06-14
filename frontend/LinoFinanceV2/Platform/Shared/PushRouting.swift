import Foundation

// PushRouting — Py ③ push deep-link routing (adapted to AppModel).
//
// v2 reimplementation of v1's `Core/Push/PushRouting`: maps a push payload's
// `target_type` to a v2 nav destination. v1 drove `AppEnvironment.selectedModule`
// + an inspector selection; v2 drives `AppModel.selection` (the macOS sidebar /
// the iOS shell observes it). AI plans live inside v2 Settings' AI card, so an
// `ai_plan` push routes to 设置.
//
// (A) wires routing + a refresh so the target is loaded; the真推 + real deep-link
// jump目视 is (B) (真机).

@MainActor
extension AppModel {
    func handlePushNotificationTarget(type: String?, id: String?) async {
        guard let type, !type.isEmpty else { return }
        switch type {
        case "credit_statement_cycle":
            selection = .cycles
            if cycles.first(where: { $0.id == id }) == nil {
                await refreshAll()
            }
        case "reimbursement_claim":
            selection = .reimbursements
            await refreshAll()
        case "ai_plan":
            // AI assistant is surfaced inside the v2 Settings page.
            selection = .settings
            if aiPlans.first(where: { $0.id == id }) == nil {
                await refreshAll()
            }
        default:
            break
        }
    }
}
