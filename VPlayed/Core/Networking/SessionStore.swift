import Foundation
#if canImport(Shared)
// Kotlin classes are not Sendable; the session manager is thread-safe.
@preconcurrency import Shared
#endif

/// Holds per-session request credentials for `RequestHeaders`, and starts and ends sessions for
/// `AccountStore`. `AppStartup` adds the geo token, which is not persisted.
///
/// Where the session lives depends on the platform:
/// - with the Kotlin shared layer (iOS, macOS) the shared `SessionManager` owns it (Keychain
///   storage, restore, the 401 rule); this store reads its tokens on every request, so native and
///   shared requests always send the same session;
/// - on visionOS (no shared layer) this store keeps it in the Keychain itself and restores it when created.
actor SessionStore {
    #if canImport(Shared)
    static let shared = SessionStore(sessions: SharedLayer.sessions)
    #else
    static let shared = SessionStore(credentials: KeychainCredentialStore())
    #endif

    struct Snapshot: Sendable {
        var accessToken: String?
        var profileID: String?
        var geoToken: String?
    }

    private var snapshot = Snapshot()
    private let credentials: (any CredentialStoring)?

    #if canImport(Shared)
    /// The shared session, when this store is backed by it.
    nonisolated let sessions: SessionManager?

    /// A store backed by the shared session manager: `signIn` / `signOut` go to it and `current()`
    /// reads its tokens, after it has restored the stored session.
    init(sessions: SessionManager) {
        self.sessions = sessions
        credentials = nil
    }
    #endif

    /// `credentials` persists the session; without one (tests, previews) it lives in memory only.
    init(credentials: (any CredentialStoring)? = nil) {
        #if canImport(Shared)
        sessions = nil
        #endif
        self.credentials = credentials
        snapshot.accessToken = credentials?.load()?.accessToken
    }

    func current() async -> Snapshot {
        #if canImport(Shared)
        if let sessions {
            try? await sessions.awaitLoaded()
            let session = sessions.session
            snapshot.accessToken = session?.accessToken
            snapshot.profileID = session?.profileId
        }
        #endif
        return snapshot
    }

    func update(_ change: @Sendable (inout Snapshot) -> Void) {
        change(&snapshot)
    }

    /// Stores a new session and sends its token from now on.
    func signIn(_ session: AuthCredentials) async {
        #if canImport(Shared)
        if let sessions {
            try? await sessions.signIn(session: AuthSession(session))
        }
        #endif
        credentials?.save(session)
        snapshot.accessToken = session.accessToken
        snapshot.profileID = session.profileID
    }

    /// Forgets the session. The geo token stays: it belongs to the device, not the account.
    func signOut() async {
        #if canImport(Shared)
        if let sessions {
            try? await sessions.signOut(reason: .user)
        }
        #endif
        credentials?.delete()
        snapshot.accessToken = nil
        snapshot.profileID = nil
    }
}
