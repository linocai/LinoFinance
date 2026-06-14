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
    /// The v1.1.x single-token account name, migrated into `.admin` in v1.2.
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

    /// One-shot v1.1 → v1.2 migration: move a legacy `linofinance.apiToken`
    /// entry into the `.admin` slot and remove the old account. Returns true
    /// when a legacy token was migrated.
    @discardableResult
    func migrateLegacyTokenIfNeeded() -> Bool {
        guard let legacy = readToken(account: legacyAccount), !legacy.isEmpty else {
            return false
        }
        try? saveToken(legacy, account: TokenKind.admin.rawValue)
        deleteToken(account: legacyAccount)
        return true
    }

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
