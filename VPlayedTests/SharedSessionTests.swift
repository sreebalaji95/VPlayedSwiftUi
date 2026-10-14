import Foundation
@preconcurrency import Shared
import Testing
@testable import VPlayed

/// Waits (up to a second) for main-thread deliveries from the shared layer to satisfy `condition`.
@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<100 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
}

private let user = AuthCredentials(
    accessToken: "access-1", refreshToken: "refresh-1", userID: "u1", uniqueUserID: 42,
    email: "user@example.com", phone: nil, firstName: "Sam", isGuest: false, profileID: "profile-1"
)

/// A store holding `value` under the session key, as an earlier launch left it.
private func store(holding value: String) -> InMemorySecureStore {
    InMemorySecureStore(initial: [SecureKey.session: value])
}

/// What the app stored before the shared session manager: `AuthCredentials` JSON.
private func legacyJSON(_ credentials: AuthCredentials) throws -> String {
    String(decoding: try JSONEncoder().encode(credentials), as: UTF8.self)
}

/// The session on the shared `SessionManager` (Phase 5), as the app wires it.
@MainActor
@Suite
struct SharedSessionTests {
    @Test func aSessionStoredByThePreviousVersionIsRestored() async throws {
        let sessions = SessionManager(store: store(holding: try legacyJSON(user)))

        try await sessions.awaitLoaded()

        let session = try #require(sessions.session)
        #expect(AuthCredentials(session) == user)
    }

    @Test func aGuestSessionStoredByThePreviousVersionIsRestoredAsAGuest() async throws {
        let guest = AuthCredentials(accessToken: "guest-1", refreshToken: nil, userID: nil, uniqueUserID: 77, email: nil, phone: nil, firstName: nil, isGuest: true)
        let sessions = SessionManager(store: store(holding: try legacyJSON(guest)))

        try await sessions.awaitLoaded()

        #expect(sessions.session.map(AuthCredentials.init) == guest)
    }

    @Test func accountStoreFollowsTheRestoredSession() async throws {
        let account = AccountStore(sessions: SessionManager(store: store(holding: try legacyJSON(user))), service: MockAuthService())

        try await waitUntil { account.isSignedIn }

        #expect(account.state == .signedIn(user))
    }

    @Test func accountStoreStartsAndEndsTheSharedSession() async throws {
        let store = InMemorySecureStore()
        let sessions = SessionManager(store: store)
        let service = MockAuthService()
        let account = AccountStore(sessions: sessions, service: service)

        await account.complete(with: user)
        #expect(sessions.session?.accessToken == "access-1")
        #expect(sessions.session?.profileId == "profile-1")
        #expect(store.peek(key: .session) != nil)

        try await account.signOut()
        #expect(service.calls == ["logout"])
        #expect(sessions.currentStatus as? SessionStatusSignedOut == SessionStatusSignedOut(reason: .user))
        #expect(store.peek(key: .session) == nil)
        #expect(account.state == .signedOut)
    }

    @Test func keychainStoreRoundTripsInTheAppsItemFormat() throws {
        let item = KeychainItem(account: "session-tests-\(UUID().uuidString)")
        defer { item.delete() }
        let keychain = KeychainSecureStore(sessionItem: item)

        #expect(keychain.read(key: .session) == nil)
        // A session the previous version stored is readable as text.
        item.save(try JSONEncoder().encode(user))
        #expect(keychain.read(key: .session).flatMap { try? JSONDecoder().decode(AuthCredentials.self, from: Data($0.utf8)) } == user)

        #expect(keychain.write(key: .session, value: #"{"format":1,"accessToken":"access-2","isGuest":false}"#))
        #expect(keychain.read(key: .session)?.contains("access-2") == true)
        keychain.delete(key: .session)
        #expect(keychain.read(key: .session) == nil)
    }
}

extension RoutedBackendTests {
    /// The 401 rule (decision D21) as the app sees it.
    @MainActor
    @Suite
    struct SharedSessionExpiryTests {
        @Test func aRejectedTokenSignsTheAccountOut() async throws {
            let sessions = SessionManager(store: store(holding: try legacyJSON(user)))
            let account = AccountStore(sessions: sessions, service: MockAuthService())
            try await waitUntil { account.isSignedIn }
            RouteStubURLProtocol.reset([RoutedBackend.route("mediaview/api/v1/common"): .json(status: 401, body: #"{"statusCode":401,"message":"Unauthorized"}"#)])
            let graph = SharedLayer.makeGraph(
                environment: .development,
                appVersion: "9.9.9",
                transportKey: "",
                deviceInfo: IOSSharedDeviceInfo(deviceId: "test-device", deviceName: "iPhone17,3", languageCode: { "en" }),
                sessions: sessions,
                engineFactory: { HttpEngine_appleKt.createDarwinEngine { $0.protocolClasses = [RouteStubURLProtocol.self] } }
            )

            _ = try await graph.apiCaller.get(path: "mediaview/api/v1/common", query: [], options: RequestOptions(sendGeoToken: true, redact: false, endsSessionOnUnauthorized: true))
            try await waitUntil { account.state == .signedOut }

            #expect(RouteStubURLProtocol.captured.first?.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
            #expect(account.state == .signedOut)
            #expect(sessions.currentStatus as? SessionStatusSignedOut == SessionStatusSignedOut(reason: .expired))
        }
    }
}
