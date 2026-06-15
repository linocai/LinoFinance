import SwiftUI

#if os(iOS)

// IOSLoginGate — iOS login wall (bugfix: iOS had no reachable login entry).
//
// On iOS the core-5 TabBar has no Settings screen (it's a 「更多」placeholder),
// so a fresh install — new bundle id, empty keychain — had NO way to sign in:
// every tab hit 401 and showed an empty state, so only the local 记一笔 ➕ sheet
// did anything. `IOSAppShell` now shows this gate whenever `!model.hasToken` and
// only mounts the TabBar once a token exists.
//
// Two paths, both reusing the existing AppModel auth plumbing:
//   • Sign in with Apple  — real Apple-ID闭环 (needs the SIWA capability + signed
//     device build; 真机 verification stays the user's step).
//   • Admin token paste   — zero-portal self-use path: paste LINOFINANCE_API_AUTH_TOKEN
//     and use the app immediately, no developer-portal work required.
//
// A successful sign-in / save calls `rebuildClients` (bumps the @Published
// `authVersion`), which re-renders `IOSAppShell` → `hasToken` flips true → tabs.

struct IOSLoginGate: View {
    @ObservedObject var model: AppModel

    @State private var showAdminEntry = false
    @State private var adminToken = ""

    var body: some View {
        ZStack {
            BloomBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    header
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            SignInWithAppleView(model: model)
                            Divider().overlay(Theme.Color.divider)
                            adminDisclosure
                        }
                    }
                    Text("数据存在云端账本；登录后双端同步。")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 72)
                .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "yensign.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.Color.brandGradient)
            Text("LinoF")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("登录以使用双币种账本")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var adminDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdminEntry) {
            VStack(alignment: .leading, spacing: 8) {
                Text("自用直连:粘贴 LINOFINANCE_API_AUTH_TOKEN 即可立即进入,无需开发者后台。")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Color.textTertiary)
                SecureField("Admin Token", text: $adminToken)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    Spacer()
                    TintedActionChip(title: "保存并进入", tone: .brand) {
                        let token = adminToken
                        adminToken = ""
                        Task { try? await model.saveAdminToken(token) }
                    }
                    .disabled(adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("高级 / 管理员 Token")
                .font(Theme.Font.caption(.medium))
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}

#endif
