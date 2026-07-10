import Foundation

// PushRouting — Py ③ push deep-link routing (adapted to AppModel).
//
// v2 reimplementation of v1's `Core/Push/PushRouting`: maps a push payload's
// `target_type` to a v2 nav destination. v1 drove `AppEnvironment.selectedModule`
// + an inspector selection; v2 drives `AppModel.selection` (the macOS sidebar /
// the iOS shell observes it).
//
// v3.1.0 P3: this is now also the landing point for a LOCAL notification tap
// (`LocalNotifications.notifyPendingProposal`), not just a remote push — both
// post the identical `target_type`/`target_id` userInfo shape through
// `.linoDidReceivePushTarget`, so a single routing function serves both without
// caring which one fired it (D5 甲: no URL scheme, reuse this exact path).
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
            // v3.1.0 P3 fix: this used to route to `.settings` — stale since
            // v3.0.0 P4 moved AI to its own `.ai` sidebar screen. macOS has a
            // real AI destination/history to land on; iOS has neither (AI
            // only lives inside 记一笔's "AI 解析" sub-sheet), so it presents
            // the ONE targeted plan via `pendingAIPlanId` instead (mirrors
            // `editingEntry`'s item-sheet pattern — see `AppModel`).
            #if os(macOS)
            selection = .ai
            if aiPlans.first(where: { $0.id == id }) == nil {
                await refreshAll()
            }
            #else
            if let id, !id.isEmpty {
                pendingAIPlanId = id
            }
            #endif
        default:
            break
        }
    }
}
