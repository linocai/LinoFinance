#if os(iOS)
import SwiftUI
import UIKit
import UserNotifications

// PushNotificationManager — Py ③ APNs push (iOS).
//
// v2 reimplementation of v1's `Platform/iOS/PushNotificationManager`: requests
// notification authorization, registers for remote notifications, and bridges the
// three UIApplicationDelegate callbacks to NotificationCenter so the SwiftUI
// shell (IOSAppShell) can react without owning a delegate. Identical mechanism to
// v1; the only difference is the consumer (AppModel, not AppEnvironment).
//
// (A) wires the manager + delegate + the registerPushDevice call. The real APNs
// token only arrives on a real device with a portal-registered Push capability —
// that闭环 is (B) (留用户).

extension Notification.Name {
    static let linoDidRegisterForRemoteNotifications = Notification.Name("linoDidRegisterForRemoteNotifications")
    static let linoDidFailRemoteNotificationRegistration = Notification.Name("linoDidFailRemoteNotificationRegistration")
    static let linoDidReceivePushTarget = Notification.Name("linoDidReceivePushTarget")
    /// v3.1.0 P3 — the "撤销" action on an auto-executed-AI local notification
    /// (see `LocalNotifications`). Kept separate from `linoDidReceivePushTarget`
    /// because its payload key space is different (an `ai_action_id` to roll
    /// back, not a `target_type`/`target_id` navigation target).
    static let linoDidRequestAIActionRollback = Notification.Name("linoDidRequestAIActionRollback")
}

@MainActor
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private init() {}

    func requestAuthorizationAndRegister() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        guard granted else {
            throw PushNotificationError.authorizationDenied
        }
        UIApplication.shared.registerForRemoteNotifications()
    }
}

final class LinoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // v3.1.0 P3 — registers the "撤销" category/action so it's attached by
        // the time a免提 execution's `LocalNotifications.notifyExecuted` first
        // fires. Safe to call unconditionally at every launch (idempotent).
        LocalNotifications.registerCategories()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCenter.default.post(
            name: .linoDidRegisterForRemoteNotifications,
            object: nil,
            userInfo: ["token": deviceToken.map { String(format: "%02x", $0) }.joined()]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: .linoDidFailRemoteNotificationRegistration,
            object: nil,
            userInfo: ["message": error.localizedDescription]
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // v3.1.0 P3 — the "撤销" action button on an auto-executed-AI
        // notification carries an `ai_action_id`, not a navigation target;
        // route it to its own notification name rather than the
        // target_type/target_id path below (an executed notification never
        // sets those keys, so this branch would be a no-op there anyway —
        // being explicit keeps the two payload shapes from ever blurring).
        if response.actionIdentifier == LocalNotifications.undoActionID,
           let actionID = userInfo["ai_action_id"] as? String {
            NotificationCenter.default.post(
                name: .linoDidRequestAIActionRollback,
                object: nil,
                userInfo: ["ai_action_id": actionID]
            )
            completionHandler()
            return
        }

        var payload: [String: String] = [:]
        if let targetType = userInfo["target_type"] as? String {
            payload["target_type"] = targetType
        }
        if let targetID = userInfo["target_id"] as? String {
            payload["target_id"] = targetID
        }
        if let deepLink = userInfo["deep_link"] as? String {
            payload["deep_link"] = deepLink
        }
        if !payload.isEmpty {
            NotificationCenter.default.post(
                name: .linoDidReceivePushTarget,
                object: nil,
                userInfo: payload
            )
        }
        completionHandler()
    }
}

enum PushNotificationError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "系统通知授权未开启"
        }
    }
}
#endif
