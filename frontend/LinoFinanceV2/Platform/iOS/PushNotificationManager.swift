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
