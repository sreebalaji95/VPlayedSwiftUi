import Foundation
import Observation
// Kotlin classes are not Sendable; the session manager is thread-safe.
@preconcurrency import Shared

/// Who is using the app: nobody, a guest or a signed-in account. `MyApp` owns it; views read it
/// from the environment.
///
/// It is a view of the shared `SessionManager`, which stores the session, sends its tokens with
/// every request and ends it when the server rejects the token (decision D21): the state follows the
/// manager's status, starting with the session it restores at launch.
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

        /// Loading reads as signed out until the stored session is known.
        init(_ status: any SessionStatus) {
            self.init((status as? SessionStatusSignedIn).map { AuthCredentials($0.session) })
        }
    }

    private(set) var state: State

    /// True for a real account; guests still see "Sign in", as in the UIKit app.
    var isSignedIn: Bool {
        if case .signedIn = state { true } else { false }
    }

    @ObservationIgnored private let sessions: SessionManager
    @ObservationIgnored private let service: any AuthServicing
    @ObservationIgnored private let watchers = KotlinSubscriptions()

    init(sessions: SessionManager = SharedLayer.sessions, service: any AuthServicing = AuthServices.live()) {
        self.sessions = sessions
        self.service = service
        state = State(sessions.currentStatus)
        watchers.add(sessions.watchStatus { [weak self] status in
            MainActor.assumeIsolated { self?.apply(status) }
        }.close)
        Task { try? await sessions.awaitLoaded() }
    }

    /// Starts the session a login returned. Only called with a real response, so a failed login
    /// never leaves a session behind.
    func complete(with credentials: AuthCredentials) async {
        try? await sessions.signIn(session: AuthSession(credentials))
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
        try? await sessions.signOut(reason: .user)
        state = .signedOut
    }

    private func apply(_ status: any SessionStatus) {
        // Still reading the stored session: keep what is shown.
        guard !(status is SessionStatusLoading) else { return }
        state = State(status)
    }
}
