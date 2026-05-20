import Foundation
import LocalAuthentication

enum PrivacyUnlockMethod: String, CaseIterable, Identifiable {
    case systemAuthentication
    case biometricsOnly
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemAuthentication: "Face ID / Touch ID / 密码"
        case .biometricsOnly: "仅 Face ID / Touch ID"
        case .never: "永不锁"
        }
    }

    var policy: LAPolicy? {
        switch self {
        case .systemAuthentication: .deviceOwnerAuthentication
        case .biometricsOnly: .deviceOwnerAuthenticationWithBiometrics
        case .never: nil
        }
    }
}

enum PrivacyIdleLockInterval: Int, CaseIterable, Identifiable {
    case five = 5
    case fifteen = 15
    case thirty = 30
    case never = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .five: "5 分钟"
        case .fifteen: "15 分钟"
        case .thirty: "30 分钟"
        case .never: "永不"
        }
    }

    var seconds: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue * 60)
    }
}

struct PrivacyAuthenticator {
    static let shared = PrivacyAuthenticator()

    func authenticate(method: PrivacyUnlockMethod) async throws -> Bool {
        guard let policy = method.policy else {
            return true
        }
        let context = LAContext()
        context.localizedCancelTitle = "保持隐藏"
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            if method == .systemAuthentication {
                return false
            }
            throw error ?? PrivacyAuthenticationError.unavailable
        }
        return try await context.evaluatePolicy(policy, localizedReason: "解锁 LinoFinance 金额显示")
    }
}

enum PrivacyAuthenticationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "当前设备不支持所选解锁方式。"
        }
    }
}
