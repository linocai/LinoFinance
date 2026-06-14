#if os(iOS) || os(macOS)
import AuthenticationServices
import SwiftUI

// SignInWithAppleView — Py ② Sign in with Apple (entitlements + button + wiring).
//
// v2 reimplementation of v1's `Features/Auth/SignInWithAppleView`, adapted to
// `AppModel` (login persists the session token to the keychain session slot,
// rebuilds the API clients, refreshes). The admin-token bypass stays valid in
// parallel — `SecureTokenStore.readEffectiveToken()` prefers the session slot
// once a SIWA session exists, so this is additive, not a replacement.
//
// (A) wires the button + the `signInWithApple` call; the real Apple-ID闭环
// (system auth → backend JWKS verify → session token) is真机 + 真 Apple ID (B).
//
// This is a self-contained card (button + status + optional admin-token entry)
// suited to embedding inside the Settings 「登录与设备」section.
struct SignInWithAppleView: View {
    @ObservedObject var model: AppModel
    /// Called after a successful sign-in so the host can reload its auth section.
    var onSignedIn: (() -> Void)?

    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    Task { await handle(result) }
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: 320, minHeight: 44)

            if isWorking {
                ProgressView("正在登录…")
                    .font(Theme.Font.caption())
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.expense)
            }
            Text("使用 Apple 账号登录以同步双端数据。管理员令牌旁路仍可并存。")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .disabled(isWorking)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            errorMessage = "Apple 登录失败：\(error.localizedDescription)"
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "未能从 Apple 凭证读取 identity token"
                return
            }
            isWorking = true
            defer { isWorking = false }
            do {
                try await model.signInWithApple(
                    identityToken: identityToken,
                    firstName: credential.fullName?.givenName,
                    lastName: credential.fullName?.familyName,
                    deviceLabel: Self.deviceLabel()
                )
                errorMessage = nil
                onSignedIn?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    static func deviceLabel() -> String {
        #if os(iOS)
        return "\(UIDevice.current.name) · iOS \(UIDevice.current.systemVersion)"
        #else
        let host = Host.current().localizedName ?? "Mac"
        return "\(host) · macOS"
        #endif
    }
}
#endif
