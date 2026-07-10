import Foundation
import Security

/// The two named tokens v1.2 keeps in the keychain.
enum TokenKind: String {
    /// Token issued by `POST /auth/apple` after a successful Apple sign-in.
    case session = "linofinance.sessionToken"
    /// Legacy / admin escape-hatch token (the env `LINOFINANCE_API_AUTH_TOKEN`).
    case admin = "linofinance.adminToken"
}

struct SecureTokenStore {
    static let shared = SecureTokenStore()

    private let service = "com.lino.linofinance"
    /// The v1.1.x single-token account name. Its one-shot v1.1→v1.2 migration
    /// caller lived in v1's `LinoFinanceApp.defaultAPIToken()` and was deleted
    /// with the rest of v1 in commit `211afea` (2026-06-14) — v2 has never
    /// called a migration, so this account is no longer read on any code path
    /// (v3.0.0 P1 audit: `readEffectiveToken()` only ever checks `.session`/
    /// `.admin`). Kept only so `clearAll()` can defensively wipe a leftover
    /// entry on machines that still carry a pre-v1.2 keychain item.
    private let legacyAccount = "linofinance.apiToken"

    func readToken(kind: TokenKind) -> String? {
        readToken(account: kind.rawValue)
    }

    func saveToken(_ token: String?, kind: TokenKind) throws {
        try saveToken(token, account: kind.rawValue)
    }

    func clear(kind: TokenKind) throws {
        deleteToken(account: kind.rawValue)
    }

    func clearAll() throws {
        deleteToken(account: TokenKind.session.rawValue)
        deleteToken(account: TokenKind.admin.rawValue)
        deleteToken(account: legacyAccount)
    }

    /// Prefer the Apple session token, then the admin token.
    func readEffectiveToken() -> String? {
        readToken(kind: .session) ?? readToken(kind: .admin)
    }

    // v3.0.0 P1: the one-shot v1.1→v1.2 `migrateLegacyTokenIfNeeded()` step was
    // removed here — its only caller was deleted with v1 in commit `211afea`
    // (2026-06-14), so it had been unreachable dead code for a month across
    // five shipped v2.x releases. `clearAll()` below still defensively deletes
    // the legacy account so a full sign-out also clears any leftover entry.

    // MARK: - Generic keychain helpers

    private func readToken(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private func saveToken(_ token: String?, account: String) throws {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            deleteToken(account: account)
            return
        }

        let data = Data(trimmed.utf8)
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func deleteToken(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Keychain 操作失败：\(status)"
        }
    }
}
