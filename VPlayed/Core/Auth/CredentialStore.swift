import Foundation
import Security

/// Where the signed-in session is kept between launches.
nonisolated protocol CredentialStoring: Sendable {
    func load() -> AuthCredentials?
    func save(_ credentials: AuthCredentials)
    func delete()
}

/// Keeps the session in the Keychain (the UIKit app kept its tokens in `UserDefaults`), with the
/// same item shape as `DeviceID`.
nonisolated struct KeychainCredentialStore: CredentialStoring {
    var service = "com.contus.vplayed"
    var account = "session"

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func load() -> AuthCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthCredentials.self, from: data)
    }

    func save(_ credentials: AuthCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let update = [kSecValueData as String: data] as CFDictionary
        if SecItemUpdate(baseQuery() as CFDictionary, update) == errSecItemNotFound {
            var attributes = baseQuery()
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            // If the Keychain is unavailable the session lasts until the app quits.
            _ = SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
