import Foundation
import Testing
@testable import VPlayed

/// Scripted `AuthServicing`. Development-only; never used by the app.
final class MockAuthService: AuthServicing, @unchecked Sendable {
    private let lock = NSLock()
    var sendResult: Result<SendCodeOutcome, any Error> = .success(.sent)
    var verifyResult: Result<VerifyOutcome, any Error> = .success(.newAccount)
    var guestResult: Result<AuthCredentials, any Error> = .failure(APIError.http(statusCode: 500))
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

final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AuthCredentials?

    init(_ credentials: AuthCredentials? = nil) { stored = credentials }

    func load() -> AuthCredentials? { lock.withLock { stored } }
    func save(_ credentials: AuthCredentials) { lock.withLock { stored = credentials } }
    func delete() { lock.withLock { stored = nil } }
}

private let user = AuthCredentials(accessToken: "token-1", refreshToken: "refresh-1", userID: "u1", uniqueUserID: 1, email: "a@b.co", phone: nil, firstName: nil, isGuest: false)
private let guest = AuthCredentials(accessToken: "guest-1", refreshToken: nil, userID: "g1", uniqueUserID: 9, email: nil, phone: nil, firstName: nil, isGuest: true)

private func authorization(_ session: SessionStore) async -> String? {
    await RequestHeaders(session: session, deviceID: "test-device", appVersion: "9.9.9", languageCode: { "en" }).values()["Authorization"]
}

@MainActor
struct CryptoJSAESTests {
    /// Test-only passphrase; the real one is a build secret (`Config/Secrets.xcconfig`).
    private let passphrase = "unit-test-passphrase"

    @Test func roundTripsInTheOpenSSLFormat() throws {
        let message = #"{"email":"tester@example.com","otp":"123456","deviceDetail":"iPhone17,3"}"#
        let encrypted = try CryptoJSAES.encrypt(message, passphrase: passphrase)

        #expect(encrypted.hasPrefix("U2FsdGVkX1")) // base64 of "Salted__"
        #expect(try CryptoJSAES.decrypt(encrypted, passphrase: passphrase) == message)
        // A fresh salt every time, as crypto-js does.
        #expect(try CryptoJSAES.encrypt(message, passphrase: passphrase) != encrypted)
    }

    @Test func readsCiphertextFromOpenSSL() throws {
        // printf '{"email":"test@example.com"}' | openssl enc -aes-256-cbc -md md5 -salt -pass pass:unit-test-passphrase -a -A
        let fromOpenSSL = "U2FsdGVkX18Y6Qdfa44XB43+WiAbE1nCj/6yMVgeKl6iv23QaD/kz5BsMrdvL+mK"
        #expect(try CryptoJSAES.decrypt(fromOpenSSL, passphrase: passphrase) == #"{"email":"test@example.com"}"#)
    }

    @Test func refusesToEncryptWithoutAPassphrase() {
        #expect(throws: CryptoJSAES.Failure.self) { try CryptoJSAES.encrypt("{}", passphrase: "") }
    }

    @Test func buildProvidesTheTransportKey() {
        // Config/Secrets.xcconfig must exist for email sign-in to work (see Secrets.example.xcconfig).
        #expect(!CryptoJSAES.authPassphrase.isEmpty)
    }

    @Test func rejectsTheWrongPassphrase() throws {
        let encrypted = try CryptoJSAES.encrypt("hello", passphrase: "right")
        #expect(throws: (any Error).self) { try CryptoJSAES.decrypt(encrypted, passphrase: "wrong") }
    }
}

@MainActor
struct AuthDecodingTests {
    @Test func decodesASignedInAccount() throws {
        let response = try Fixture.payload("auth-verify", as: AuthResponse.self)
        let credentials = try #require(response.credentials)

        #expect(credentials.accessToken == "test-access-token")
        #expect(credentials.refreshToken == "test-refresh-token")
        #expect(credentials.userID == "user-abc123")
        #expect(credentials.uniqueUserID == 4211)
        #expect(credentials.email == "tester@example.com")
        #expect(credentials.phone == nil)
        #expect(!credentials.isGuest)
        #expect(credentials.displayName == "Test")
        #expect(response.hasLinkedSignIn) // google_auth_id
    }

    @Test func decodesAGuestAndPrefersGuestUserID() throws {
        let response = try Fixture.payload("auth-guest", as: AuthResponse.self)
        let credentials = try #require(response.credentials)

        #expect(credentials.isGuest)
        #expect(credentials.uniqueUserID == 9001)
    }

    @Test func unlinkedAccountsAndMissingTokens() throws {
        let unlinked = try JSONDecoder().decode(AuthResponse.self, from: Data(#"{"access_token":"t","email":"a@b.co","phone":null}"#.utf8))
        #expect(!unlinked.hasLinkedSignIn)
        #expect(unlinked.credentials != nil)

        // An empty phone string still counts, as with SwiftyJSON's `.string`.
        let emptyPhone = try JSONDecoder().decode(AuthResponse.self, from: Data(#"{"access_token":"t","phone":""}"#.utf8))
        #expect(emptyPhone.hasLinkedSignIn)

        let noToken = try JSONDecoder().decode(AuthResponse.self, from: Data(#"{"email":"a@b.co","google_auth_id":"g"}"#.utf8))
        #expect(noToken.credentials == nil)
    }

    @Test func authEndpointsMatchTheUIKitURLs() throws {
        let base = APIEnvironment.development.apiBaseURL
        #expect(try Endpoint.emailLogin.url(relativeTo: base).absoluteString == "https://api-devgs.vplayed.com/users/api/v1/auth/email-login")
        #expect(try Endpoint.verifyEmailOTP.url(relativeTo: base).absoluteString == "https://api-devgs.vplayed.com/users/api/v1/auth/verifyEmailOtp")
        #expect(try Endpoint.guestLogin.url(relativeTo: base).absoluteString == "https://api-devgs.vplayed.com/users/api/v1/auth/generate")
        #expect(try Endpoint.logout.url(relativeTo: base).absoluteString == "https://api-devgs.vplayed.com/users/api/v1/auth/logout")
    }
}

@MainActor
struct LoginViewModelTests {
    private func makeModel(_ service: MockAuthService, session: SessionStore = SessionStore()) -> (LoginViewModel, AccountStore) {
        let account = AccountStore(saved: nil, session: session, service: service)
        return (LoginViewModel(account: account, service: service), account)
    }

    @Test func emailValidationMatchesUIKit() {
        #expect(LoginViewModel.isValidEmail("tester@example.com"))
        #expect(LoginViewModel.isValidEmail("first.last+tag@sub.example.co"))
        #expect(!LoginViewModel.isValidEmail(""))
        #expect(!LoginViewModel.isValidEmail("tester@example"))
        #expect(!LoginViewModel.isValidEmail("tester example.com"))
    }

    @Test func emptyOrInvalidEmailShowsAnErrorWithoutCallingTheAPI() async {
        let service = MockAuthService()
        let (model, _) = makeModel(service)

        await model.continueWithEmail()
        #expect(model.emailError != nil)

        model.email = "not-an-email"
        #expect(model.emailError == nil) // typing clears it
        await model.continueWithEmail()
        #expect(model.emailError != nil)
        #expect(service.calls.isEmpty)
        #expect(model.step == .email)
    }

    @Test func emailIsTrimmedAndCappedAt50Characters() async {
        let service = MockAuthService()
        let (model, _) = makeModel(service)

        model.email = String(repeating: "a", count: 60)
        #expect(model.email.count == LoginViewModel.maxEmailLength)

        model.email = "  tester@example.com "
        await model.continueWithEmail()
        #expect(service.calls == ["send:tester@example.com"])
        #expect(model.step == .code)
        #expect(model.sentTo == "tester@example.com")
        #expect(model.resendSeconds == LoginViewModel.resendInterval)
        model.stopTimers()
    }

    @Test func aDoubleTapSendsOnce() async {
        let service = MockAuthService()
        service.sendDelay = .milliseconds(100)
        let (model, _) = makeModel(service)
        model.email = "tester@example.com"

        async let first: Void = model.continueWithEmail()
        async let second: Void = model.continueWithEmail()
        _ = await (first, second)

        #expect(service.calls.count == 1)
        model.stopTimers()
    }

    @Test func newAccountStaysOnTheEmailStep() async {
        let service = MockAuthService()
        service.sendResult = .success(.newAccount)
        let (model, _) = makeModel(service)
        model.email = "new@example.com"

        await model.continueWithEmail()

        #expect(model.step == .email)
        #expect(model.notice != nil)
    }

    @Test func sendFailureShowsTheServerMessage() async {
        let service = MockAuthService()
        service.sendResult = .failure(APIError.api(statusCode: 422, message: "Too many attempts"))
        let (model, _) = makeModel(service)
        model.email = "tester@example.com"

        await model.continueWithEmail()

        #expect(model.notice == "Too many attempts")
        #expect(model.step == .email)
    }

    @Test func codeAcceptsOnlySixDigits() {
        let (model, _) = makeModel(MockAuthService())
        model.code = "12a3-45678"
        #expect(model.code == "123456")
        #expect(model.canVerify)
        model.code = "123"
        #expect(!model.canVerify)
    }

    @Test func verifySuccessStoresTheSessionAndFinishes() async {
        let service = MockAuthService()
        service.verifyResult = .success(.signedIn(user))
        let session = SessionStore()
        let (model, account) = makeModel(service, session: session)
        model.email = "a@b.co"
        await model.continueWithEmail()

        model.code = "123456"
        await model.verify()

        #expect(service.calls.last == "verify:123456:a@b.co")
        #expect(model.step == .done)
        #expect(account.state == .signedIn(user))
        #expect(account.isSignedIn)
        #expect(await authorization(session) == "Bearer token-1")
    }

    @Test(arguments: [
        VerifyOutcome.deviceLimit(message: "Signed in on 2 devices"),
        VerifyOutcome.newAccount,
    ])
    func verifyOutcomesThatDoNotSignIn(outcome: VerifyOutcome) async {
        let service = MockAuthService()
        service.verifyResult = .success(outcome)
        let session = SessionStore()
        let (model, account) = makeModel(service, session: session)
        model.email = "a@b.co"
        await model.continueWithEmail()

        model.code = "123456"
        await model.verify()

        #expect(model.step == .code)
        #expect(model.code.isEmpty)
        #expect(model.notice != nil)
        if case .deviceLimit = outcome { #expect(model.notice == "Signed in on 2 devices") }
        #expect(account.state == .signedOut)
        #expect(await authorization(session) == nil)
        model.stopTimers()
    }

    @Test func wrongCodeClearsItAndKeepsTheSessionEmpty() async {
        let service = MockAuthService()
        service.verifyResult = .failure(APIError.api(statusCode: 400, message: "Invalid OTP"))
        let session = SessionStore()
        let (model, account) = makeModel(service, session: session)
        model.email = "a@b.co"
        await model.continueWithEmail()

        model.code = "000000"
        await model.verify()

        #expect(model.notice == "Invalid OTP")
        #expect(model.code.isEmpty)
        #expect(!model.isVerifying)
        #expect(account.state == .signedOut)
        #expect(await authorization(session) == nil)
        model.stopTimers()
    }

    @Test func editEmailGoesBackAndStopsTheTimer() async {
        let (model, _) = makeModel(MockAuthService())
        model.email = "a@b.co"
        await model.continueWithEmail()

        model.editEmail()

        #expect(model.step == .email)
        #expect(model.resendSeconds == 0)
        #expect(model.email == "a@b.co")
    }

    @Test func guestSuccessStartsAGuestSession() async {
        let service = MockAuthService()
        service.guestResult = .success(guest)
        let session = SessionStore()
        let (model, account) = makeModel(service, session: session)

        await model.continueAsGuest()

        #expect(model.isFinished)
        #expect(account.state == .guest(guest))
        #expect(!account.isSignedIn)
        #expect(await authorization(session) == "Bearer guest-1")
    }

    @Test func guestFailureCreatesNoSessionAndCanRetry() async {
        let service = MockAuthService()
        service.guestResult = .failure(APIError.network(code: URLError.notConnectedToInternet.rawValue))
        let session = SessionStore()
        let (model, account) = makeModel(service, session: session)

        await model.continueAsGuest()

        #expect(!model.isFinished)
        #expect(model.notice != nil)
        #expect(!model.isJoiningAsGuest)
        #expect(account.state == .signedOut)
        #expect(await authorization(session) == nil)

        service.guestResult = .success(guest)
        await model.continueAsGuest()
        #expect(account.state == .guest(guest))
    }
}

@MainActor
struct AccountStoreTests {
    @Test func restoresTheSavedSession() async {
        let store = InMemoryCredentialStore(user)
        let session = SessionStore(credentials: store)
        let account = AccountStore(saved: store.load(), session: session, service: MockAuthService())

        #expect(account.state == .signedIn(user))
        #expect(await authorization(session) == "Bearer token-1")
        #expect(AccountStore.State(guest) == .guest(guest))
        #expect(AccountStore.State(nil) == .signedOut)
    }

    @Test func signInPersistsAndSignOutForgets() async throws {
        let store = InMemoryCredentialStore()
        let session = SessionStore(credentials: store)
        let service = MockAuthService()
        let account = AccountStore(saved: nil, session: session, service: service)

        await account.complete(with: user)
        #expect(store.load() == user)

        try await account.signOut()
        #expect(service.calls == ["logout"])
        #expect(store.load() == nil)
        #expect(account.state == .signedOut)
        #expect(await authorization(session) == nil)
    }

    @Test func signOutClearsWhenTheTokenIsAlreadyRejected() async throws {
        let store = InMemoryCredentialStore(user)
        let service = MockAuthService()
        service.logoutResult = .failure(APIError.unauthorized)
        let account = AccountStore(saved: user, session: SessionStore(credentials: store), service: service)

        try await account.signOut()

        #expect(account.state == .signedOut)
        #expect(store.load() == nil)
    }

    @Test func otherLogoutFailuresKeepTheSession() async {
        let store = InMemoryCredentialStore(user)
        let session = SessionStore(credentials: store)
        let service = MockAuthService()
        service.logoutResult = .failure(APIError.network(code: URLError.timedOut.rawValue))
        let account = AccountStore(saved: user, session: session, service: service)

        await #expect(throws: APIError.self) { try await account.signOut() }

        #expect(account.state == .signedIn(user))
        #expect(store.load() == user)
        #expect(await authorization(session) == "Bearer token-1")
    }
}
