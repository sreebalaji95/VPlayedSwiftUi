import Foundation
import Security

/// A stable per-install device identifier stored in the Keychain under `deviceId`,
/// matching the key the UIKit app uses for the `device_id` header.
nonisolated enum DeviceID {
    static let current: String = load() ?? create()

    private static let service = "com.contus.vplayed"
    private static let account = "deviceId"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func create() -> String {
        let value = UUID().uuidString
        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // If the Keychain is unavailable the ID simply isn't persisted; requests still work.
        _ = SecItemAdd(attributes as CFDictionary, nil)
        return value
    }
}
