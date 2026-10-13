import Foundation

/// Holds per-session request credentials for `RequestHeaders`. The shared store restores the
/// signed-in (or guest) session from the Keychain when it is created, so the first request after
/// a relaunch is already authenticated. `AppStartup` adds the geo token, which is not persisted.
actor SessionStore {
    static let shared = SessionStore(credentials: KeychainCredentialStore())

    struct Snapshot: Sendable {
        var accessToken: String?
        var profileID: String?
        var geoToken: String?
    }

    private var snapshot = Snapshot()
    private let credentials: (any CredentialStoring)?

    /// `credentials` persists the session; without one (tests, previews) it lives in memory only.
    init(credentials: (any CredentialStoring)? = nil) {
        self.credentials = credentials
        snapshot.accessToken = credentials?.load()?.accessToken
    }

    func current() -> Snapshot { snapshot }

    func update(_ change: @Sendable (inout Snapshot) -> Void) {
        change(&snapshot)
    }

    /// Stores a new session and sends its token from now on.
    func signIn(_ session: AuthCredentials) {
        credentials?.save(session)
        snapshot.accessToken = session.accessToken
    }

    /// Forgets the session. The geo token stays: it belongs to the device, not the account.
    func signOut() {
        credentials?.delete()
        snapshot.accessToken = nil
        snapshot.profileID = nil
    }
}
