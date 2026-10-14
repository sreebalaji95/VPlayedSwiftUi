import Foundation
@preconcurrency import Shared
import Testing
@testable import VPlayed

/// Scripted `AuthServicing`. Development-only; never used by the app.
final class MockAuthService: AuthServicing, @unchecked Sendable {
    private let lock = NSLock()
    var sendResult: Result<SendCodeOutcome, any Error> = .success(.sent)
    var verifyResult: Result<VerifyOutcome, any Error> = .success(.newAccount)
    var guestResult: Result<AuthCredentials, any Error> = .failure(APIError.api(statusCode: 500, message: nil))
    var logoutResult: Result<Void, any Error> = .success(())
    var sendDelay: Duration?
    private var log: [String] = []

    var calls: [String] { lock.withLock { log } }

    func sendEmailCode(to email: String) async throws -> SendCodeOutcome {
        lock.withLock { log.append("send:\(email)") }
        if let sendDelay { try await Task.sleep(for: sendDelay) }
        return try sendResult.get()
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> VerifyOutcome {
        lock.withLock { log.append("verify:\(code):\(email)") }
        return try verifyResult.get()
    }

    func guestLogin() async throws -> AuthCredentials {
        lock.withLock { log.append("guest") }
        return try guestResult.get()
    }

    func logout() async throws {
        lock.withLock { log.append("logout") }
        try logoutResult.get()
    }
}

private let user = AuthCredentials(accessToken: "token-1", refreshToken: "refresh-1", userID: "u1", uniqueUserID: 1, email: "a@b.co", phone: nil, firstName: nil, isGuest: false)
private let guest = AuthCredentials(accessToken: "guest-1", refreshToken: nil, userID: "g1", uniqueUserID: 9, email: nil, phone: nil, firstName: nil, isGuest: true)

/// A session manager already signed in as `credentials` (in memory).
private func signedIn(_ credentials: AuthCredentials) async throws -> SessionManager {
    let sessions = SessionManager(store: InMemorySecureStore())
    try await sessions.signIn(session: AuthSession(credentials))
    return sessions
}

@MainActor
struct AccountStoreTests {
    @Test func stateReflectsTheSession() async throws {
        let account = AccountStore(sessions: try await signedIn(user), service: MockAuthService())

        #expect(account.state == .signedIn(user))
        #expect(account.isSignedIn)
        #expect(AccountStore.State(guest) == .guest(guest))
        #expect(AccountStore.State(nil) == .signedOut)
    }

    @Test func aGuestIsNotSignedIn() async throws {
        let account = AccountStore(sessions: try await signedIn(guest), service: MockAuthService())

        #expect(account.state == .guest(guest))
        #expect(!account.isSignedIn)
    }

    @Test func signOutClearsWhenTheTokenIsAlreadyRejected() async throws {
        let sessions = try await signedIn(user)
        let service = MockAuthService()
        service.logoutResult = .failure(APIError.unauthorized)
        let account = AccountStore(sessions: sessions, service: service)

        try await account.signOut()

        #expect(account.state == .signedOut)
        #expect(sessions.session == nil)
    }

    @Test func otherLogoutFailuresKeepTheSession() async throws {
        let sessions = try await signedIn(user)
        let service = MockAuthService()
        service.logoutResult = .failure(APIError.network(code: URLError.timedOut.rawValue))
        let account = AccountStore(sessions: sessions, service: service)

        await #expect(throws: APIError.self) { try await account.signOut() }

        #expect(account.state == .signedIn(user))
        #expect(sessions.session?.accessToken == "token-1")
    }

    @Test func buildProvidesTheTransportKey() {
        // Config/Secrets.xcconfig must exist for email sign-in to work (see Secrets.example.xcconfig).
        #expect(!SharedLayer.transportKey.isEmpty)
    }
}
