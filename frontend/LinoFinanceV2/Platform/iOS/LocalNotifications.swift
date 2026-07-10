#if os(iOS)
import UserNotifications

// LocalNotifications — v3.1.0 P3 免提确认闭环 (iOS only, new scheduling infra).
//
// Schedules the two feedback notifications a headless `AIIntentService`
// invocation (Siri / Shortcuts / Back Tap) can produce, on top of its spoken
// `IntentDialog` reply:
//   • `notifyExecuted`      — auto-recorded successfully; carries a "撤销"
//                             action mapped to `rollbackAIAction`.
//   • `notifyPendingProposal` — left as a pending proposal; tapping it MUST
//                             route through the exact same path a remote
//                             high-risk-plan push already uses
//                             (`PushNotificationManager` →
//                             `.linoDidReceivePushTarget` →
//                             `AppModel.handlePushNotificationTarget`), so its
//                             userInfo deliberately reuses the backend's
//                             `push_dispatch._apns_payload` key names —
//                             `target_type` / `target_id` — verbatim (D5 甲:
//                             no URL scheme, one routing surface for both a
//                             remote push and a local notification).
//   • `notifyRollbackResult` — feedback for the "撤销" action itself (success
//                             or failure), since a notification action has no
//                             screen to show either outcome on.
//
// Authorization (D6): every entry point calls `requestAuthorizationIfNeeded()`
// first, which REUSES `PushNotificationManager`'s existing authorization flow
// rather than forking a second one ("复用既有授权流"). That call is safe to
// make unconditionally — iOS only ever shows the system permission prompt
// once (`.notDetermined`); once the user has answered, every subsequent call
// returns that same answer immediately with no dialog. So this both (a)
// actively triggers the first-time prompt at the moment it's actually needed
// (immediate/免提 execution), satisfying D6's "首次免提前若通知未授权 →
// 触发 requestAuthorization", and (b) never re-prompts or blocks a user who
// already said no — a denial just makes every notify* call a no-op, and the
// spoken Siri/Shortcuts reply remains the only feedback (D6: never blocks the
// headless reply on notification permission).
enum LocalNotifications {
    /// "撤销" action + its category, registered once at launch
    /// (`LinoAppDelegate.didFinishLaunchingWithOptions`) so the action button
    /// is attached by the time `notifyExecuted` first fires.
    static let executedCategoryID = "AI_EXECUTED"
    static let undoActionID = "AI_UNDO_ACTION"

    static func registerCategories() {
        let undo = UNNotificationAction(identifier: undoActionID, title: "撤销", options: [])
        let category = UNNotificationCategory(
            identifier: executedCategoryID,
            actions: [undo],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Auto-executed successfully. `actionId` is the ONE executed
    /// `AIActionDTO.id` — the unit `POST /ai/actions/{action_id}/rollback`
    /// operates on (NOT the plan id) — mirroring `AIPlanHistoryRow`'s own
    /// "回滚" lookup (`actions.first(where: { $0.status == "executed" })`) so
    /// both surfaces agree on what a rollback targets.
    static func notifyExecuted(summary: String, actionId: String) async {
        guard await requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "已自动记账"
        content.body = summary
        content.sound = .default
        content.categoryIdentifier = executedCategoryID
        content.userInfo = ["ai_action_id": actionId]
        let request = UNNotificationRequest(identifier: "ai-executed-\(actionId)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Left as a pending proposal (medium/high risk, or an incomplete
    /// account/category id) — `planId` feeds the SAME `target_type=ai_plan` /
    /// `target_id` shape `push_dispatch.dispatch_high_risk_ai_plan` already
    /// sends for a remote push.
    static func notifyPendingProposal(summary: String, planId: String) async {
        guard await requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "AI 提案待确认"
        content.body = summary
        content.sound = .default
        content.userInfo = ["target_type": "ai_plan", "target_id": planId]
        let request = UNNotificationRequest(identifier: "ai-pending-\(planId)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Feedback for the "撤销" action itself — always fires (success or
    /// failure) since a notification action runs with no screen to show
    /// either outcome on; silence-on-failure would look identical to a
    /// successful undo.
    static func notifyRollbackResult(success: Bool, message: String) async {
        guard await requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = success ? "已撤销" : "撤销失败"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: "ai-rollback-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func requestAuthorizationIfNeeded() async -> Bool {
        do {
            try await PushNotificationManager.shared.requestAuthorizationAndRegister()
            return true
        } catch {
            return false
        }
    }
}
#endif
