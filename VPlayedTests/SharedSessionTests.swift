#if canImport(Shared)
import Foundation
@preconcurrency import Shared
import Testing
@testable import VPlayed

/// Waits (up to a second) for main-thread deliveries from the shared layer to satisfy `condition`.
@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<100 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
}

private let user = AuthCredentials(
    accessToken: "access-1", refreshToken: "refresh-1", userID: "u1", uniqueUserID: 42,
    email: "user@example.com", phone: nil, firstName: "Sam", isGuest: false, profileID: "profile-1"
)

/// The macOS build cannot write to the data-protection Keychain (its signing has no keychain access
/// group), before and after the shared session manager: there the session lasts until the app quits.
private let keychainRefusesWrites: Bool = {
    #if os(macOS)
    true
    #else
    false
    #endif
}()

/// A store holding `value` under the session key, as an earlier launch left it.
private func store(holding value: String) -> InMemorySecureStore {
    InMemorySecureStore(initial: [SecureKey.session: value])
}

/// The session on the shared `SessionManager` (Phase 5), as the app wires it.
@MainActor
@Suite
struct SharedSessionTests {
    @Test func aSessionStoredByThePreviousVersionIsRestored() async throws {
        // What `KeychainCredentialStore` wrote before the shared session manager: `AuthCredentials` JSON.
        let legacy = String(decoding: try JSONEncoder().encode(user), as: UTF8.self)
        let sessions = SessionManager(store: store(holding: legacy))

        try await sessions.awaitLoaded()

        let session = try #require(sessions.session)
        #expect(AuthCredentials(session) == user)
    }

    @Test func aGuestSessionStoredByThePreviousVersionIsRestoredAsAGuest() async throws {
        let guest = AuthCredentials(accessToken: "guest-1", refreshToken: nil, userID: nil, uniqueUserID: 77, email: nil, phone: nil, firstName: nil, isGuest: true)
        let sessions = SessionManager(store: store(holding: String(decoding: try JSONEncoder().encode(guest), as: UTF8.self)))

        try await sessions.awaitLoaded()

        #expect(sessions.session.map(AuthCredentials.init) == guest)
    }

    @Test func sessionStoreStartsAndEndsTheSharedSession() async throws {
        let sessions = SessionManager(store: InMemorySecureStore())
        let store = SessionStore(sessions: sessions)
        await store.update { $0.geoToken = "geo-1" }

        await store.signIn(user)
        #expect(sessions.session?.accessToken == "access-1")
        var snapshot = await store.current()
        #expect(snapshot.accessToken == "access-1")
        #expect(snapshot.profileID == "profile-1")

        await store.signOut()
        #expect(sessions.currentStatus as? SessionStatusSignedOut == SessionStatusSignedOut(reason: .user))
        snapshot = await store.current()
        #expect(snapshot.accessToken == nil)
        #expect(snapshot.profileID == nil)
        // The geo token belongs to the device, not the account.
        #expect(snapshot.geoToken == "geo-1")
    }

    @Test func nativeRequestsReadTheRestoredSession() async throws {
        let stored = String(decoding: try JSONEncoder().encode(user), as: UTF8.self)
        let store = SessionStore(sessions: SessionManager(store: store(holding: stored)))

        // No explicit load: `current()` waits for the stored session, as shared requests do.
        let snapshot = await store.current()

        #expect(snapshot.accessToken == "access-1")
        #expect(snapshot.profileID == "profile-1")
    }

    @Test func accountStoreFollowsTheRestoredSession() async throws {
        let stored = String(decoding: try JSONEncoder().encode(user), as: UTF8.self)
        let session = SessionStore(sessions: SessionManager(store: store(holding: stored)))

        let account = AccountStore(saved: nil, session: session, service: MockAuthService())
        try await eventually { account.isSignedIn }

        #expect(account.state == .signedIn(user))
    }

    @Test(.disabled(if: keychainRefusesWrites, "The macOS build has no keychain access group"))
    func keychainStoreRoundTripsInTheAppsItemFormat() throws {
        let item = KeychainCredentialStore(account: "session-tests-\(UUID().uuidString)")
        defer { item.delete() }
        let keychain = KeychainSecureStore(sessionItem: item)

        #expect(keychain.read(key: .session) == nil)
        // A session the previous version stored is readable as text.
        item.save(user)
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
            let stored = String(decoding: try JSONEncoder().encode(user), as: UTF8.self)
            let sessions = SessionManager(store: store(holding: stored))
            let account = AccountStore(saved: nil, session: SessionStore(sessions: sessions), service: MockAuthService())
            try await eventually { account.isSignedIn }
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
            try await eventually { account.state == .signedOut }

            #expect(RouteStubURLProtocol.captured.first?.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
            #expect(account.state == .signedOut)
            #expect(sessions.currentStatus as? SessionStatusSignedOut == SessionStatusSignedOut(reason: .expired))
        }
    }
}
#endif
