#if canImport(Shared)
import Foundation
// Kotlin protocols and enums are not Sendable; this store is only called through `DispatchingSecureStore`.
@preconcurrency import Shared

/// The shared `SessionManager`'s secure storage: the Keychain item the app has always kept its
/// session in (service `com.contus.vplayed`, account `session`, through `KeychainCredentialStore`),
/// so a signed-in user stays signed in after the move to the shared layer (`SessionCodec` reads the
/// `AuthCredentials` JSON stored there before). Values are UTF-8 text. Called on a background thread.
nonisolated final class KeychainSecureStore: NSObject, BlockingSecureStore, @unchecked Sendable {
    private let sessionItem: KeychainCredentialStore

    init(sessionItem: KeychainCredentialStore = KeychainCredentialStore()) {
        self.sessionItem = sessionItem
    }

    func read(key: SecureKey) -> String? {
        item(for: key).loadData().flatMap { String(data: $0, encoding: .utf8) }
    }

    func write(key: SecureKey, value: String) -> Bool {
        item(for: key).saveData(Data(value.utf8))
    }

    func delete(key: SecureKey) {
        item(for: key).delete()
    }

    /// `SecureKey` has one case today (`session`).
    private func item(for key: SecureKey) -> KeychainCredentialStore {
        sessionItem
    }
}
#endif
