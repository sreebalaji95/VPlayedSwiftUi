import Foundation
import Observation

/// Who is using the app: nobody, a guest or a signed-in account. `MyApp` owns it; views read it
/// from the environment. It restores the saved session at launch, and every change also goes to
/// `SessionStore`, so requests carry the matching `Authorization` header.
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

    init(
        saved: AuthCredentials? = KeychainCredentialStore().load(),
        session: SessionStore = .shared,
        service: any AuthServicing = AuthService()
    ) {
        state = State(saved)
        self.session = session
        self.service = service
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
}
