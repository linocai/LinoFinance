#if os(iOS) || os(macOS)
import AuthenticationServices
import SwiftUI

struct SignInWithAppleView: View {
    @Bindable var environment: AppEnvironment
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("LinoFinance")
                    .font(.largeTitle.bold())
                Text("使用 Apple 账号登录以同步双端数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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
            .frame(maxWidth: 320, minHeight: 48)
            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.horizontal)
            }
            if isWorking {
                ProgressView("正在登录…")
            }
            Spacer()
            DisclosureGroup("高级设置 / 管理员 Token") {
                AdminTokenEntryView(environment: environment)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
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
                try await environment.signInWithApple(
                    identityToken: identityToken,
                    firstName: credential.fullName?.givenName,
                    lastName: credential.fullName?.familyName,
                    deviceLabel: Self.deviceLabel()
                )
                errorMessage = nil
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

struct AdminTokenEntryView: View {
    @Bindable var environment: AppEnvironment
    @State private var token = ""
    @State private var savedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("仅在使用 LINOFINANCE_API_AUTH_TOKEN 直连后端时填写。")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Admin Token", text: $token)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            HStack {
                if let savedMessage {
                    Text(savedMessage)
                        .font(.caption)
                        .foregroundStyle(FinanceTokens.State.income)
                }
                Spacer()
                Button("保存") {
                    Task {
                        try? await environment.saveAdminToken(token)
                        token = ""
                        savedMessage = "已保存管理员 Token"
                    }
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 4)
    }
}

/// Shared "已登录设备" list used by both the iOS and macOS Settings.
struct AuthSessionsSection: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        ForEach(environment.activeSessions) { session in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.deviceLabel)
                        .font(.subheadline.weight(.semibold))
                    if session.isCurrent {
                        Text("本机")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(FinanceTokens.Brand.primary.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Button(session.isCurrent ? "本机：退出登录" : "撤销", role: .destructive) {
                        Task { try? await environment.revokeSession(session.id) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                DetailLine(title: "平台", value: session.platform)
                DetailLine(title: "最近活跃", value: FinanceFormatter.mediumDate(session.lastSeenAt))
            }
            .padding(.vertical, 4)
        }
    }
}
#endif
