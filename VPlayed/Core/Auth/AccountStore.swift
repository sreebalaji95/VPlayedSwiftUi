import Foundation
import Observation
#if canImport(Shared)
@preconcurrency import Shared
#endif

/// Who is using the app: nobody, a guest or a signed-in account. `MyApp` owns it; views read it
/// from the environment. Every change goes to `SessionStore`, so requests carry the matching
/// `Authorization` header.
///
/// With the shared layer (iOS, macOS) it follows the shared `SessionManager`: the session it
/// restores at launch, and its end when the server rejects the token (decision D21). On visionOS
/// it restores the saved session from the Keychain itself.
@Observable
final class AccountStore {
    enum State: Equatable {
        case signedOut
        case guest(AuthCredentials)
        case signedIn(AuthCredentials)

        init(_ credentials: AuthCredentials?) {
            switch credentials {
            case nil: self = .signedOut
            case let credentials? where credentials.isGuest: self = .guest(credentials)
            case let credentials?: self = .signedIn(credentials)
            }
        }
    }

    private(set) var state: State

    /// True for a real account; guests still see "Sign in", as in the UIKit app.
    var isSignedIn: Bool {
        if case .signedIn = state { true } else { false }
    }

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let service: any AuthServicing
    #if canImport(Shared)
    @ObservationIgnored private let watchers = KotlinSubscriptions()
    #endif

    init(
        saved: AuthCredentials? = AccountStore.savedCredentials(),
        session: SessionStore = .shared,
        service: any AuthServicing = AuthServices.live()
    ) {
        state = State(saved)
        self.session = session
        self.service = service
        #if canImport(Shared)
        if let sessions = session.sessions { follow(sessions) }
        #endif
    }

    /// The session saved by an earlier launch, read synchronously where this store restores it (visionOS).
    static func savedCredentials() -> AuthCredentials? {
        #if canImport(Shared)
        // The shared `SessionManager` restores it; `follow(_:)` applies it.
        nil
        #else
        KeychainCredentialStore().load()
        #endif
    }

    /// Starts the session a login returned. Only called with a real response, so a failed login
    /// never leaves a session behind.
    func complete(with credentials: AuthCredentials) async {
        await session.signIn(credentials)
        state = State(credentials)
    }

    /// Logs out on the server, then forgets the session. As in the UIKit app, a failed logout
    /// keeps it, except when the server already rejects the token.
    func signOut() async throws {
        do {
            try await service.logout()
        } catch APIError.unauthorized {
            // The session is already gone on the server.
        }
        await session.signOut()
        state = .signedOut
    }

    #if canImport(Shared)
    private func follow(_ sessions: SessionManager) {
        watchers.add(sessions.watchStatus { [weak self] status in
            MainActor.assumeIsolated { self?.apply(status) }
        }.close)
        Task { try? await sessions.awaitLoaded() }
    }

    private func apply(_ status: any SessionStatus) {
        switch status {
        case let signedIn as SessionStatusSignedIn:
            state = State(AuthCredentials(signedIn.session))
        case is SessionStatusSignedOut:
            state = .signedOut
        default:
            // Still reading the stored session.
            break
        }
    }
    #endif
}
