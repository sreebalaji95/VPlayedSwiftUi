import Foundation
import Security
// Kotlin protocols and enums are not Sendable; this store is only called through `DispatchingSecureStore`.
@preconcurrency import Shared

/// The shared `SessionManager`'s secure storage: the Keychain item the app has always kept its
/// session in (service `com.contus.vplayed`, account `session`), so a signed-in user stays signed in
/// after the move to the shared layer (`SessionCodec` reads the `AuthCredentials` JSON stored there
/// before). Values are UTF-8 text. Called on a background thread.
nonisolated final class KeychainSecureStore: NSObject, BlockingSecureStore, @unchecked Sendable {
    private let sessionItem: KeychainItem

    init(sessionItem: KeychainItem = KeychainItem(account: "session")) {
        self.sessionItem = sessionItem
    }

    func read(key: SecureKey) -> String? {
        item(for: key).load().flatMap { String(data: $0, encoding: .utf8) }
    }

    func write(key: SecureKey, value: String) -> Bool {
        item(for: key).save(Data(value.utf8))
    }

    func delete(key: SecureKey) {
        item(for: key).delete()
    }

    /// `SecureKey` has one case today (`session`).
    private func item(for key: SecureKey) -> KeychainItem {
        sessionItem
    }
}

/// One generic-password Keychain item of the app (service `com.contus.vplayed`, the same item shape
/// as `DeviceID`), available after the first unlock.
nonisolated struct KeychainItem: Sendable {
    var service = "com.contus.vplayed"
    var account: String

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func load() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// False when the Keychain refused the item.
    @discardableResult
    func save(_ data: Data) -> Bool {
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery() as CFDictionary, update)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
