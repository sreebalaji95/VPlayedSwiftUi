#if canImport(Shared)
import Foundation
@preconcurrency import Shared
import Testing
@testable import VPlayed

/// Captures requests for `SharedLayerTests` (its own state, so suites running in parallel never share stubs).
final class SharedStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func reset() { lock.withLock { requests = [] } }

    static var captured: [URLRequest] { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.requests.append(request) }
        let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"statusCode":200,"response":{}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The Kotlin Multiplatform shared layer, as linked into the app (iOS and macOS; there is no visionOS slice).
@MainActor
@Suite(.serialized)
struct SharedLayerTests {
    /// Headers the backend reads. `Content-Type` is left out: `RequestHeaders` sends it on every
    /// request (even GETs), the shared client only with a body (divergence D19, harmless).
    private static let backendHeaders = [
        "Accept", "X-Request-Type", "device_type", "app_version", "X-Language-Code",
        "device_id", "Authorization", "profile_id", "X-Bearer-Token",
    ]

    @Test func environmentsMapToTheSameIdsAsAndroid() {
        #expect(SharedLayer.serverEnvironment(for: .development) == .development)
        #expect(SharedLayer.serverEnvironment(for: .qa) == .qa)
        #expect(SharedLayer.serverEnvironment(for: .staging) == .staging)
        #expect(SharedLayer.serverEnvironment(for: .demo) == .demo)
        #expect(ServerEnvironment.qa.id == "qa")
    }

    @Test func configUsesTheNativeHostsVersionAndKey() {
        let config = SharedLayer.sharedConfig(environment: .staging, appVersion: "9.9.9", transportKey: "unit-test-passphrase")

        #expect(config.serverUrl == APIEnvironment.staging.apiBaseURL.absoluteString)
        #expect(config.imageBaseUrl == APIEnvironment.staging.imageBaseURL.absoluteString)
        #expect(config.appVersion == "9.9.9")
        #expect(config.platform == .ios)
        #expect(config.transportKey == "unit-test-passphrase")
        #expect(!config.description.contains("unit-test-passphrase"))
    }

    @Test func sessionChangesReachTheSharedCredentials() async {
        let credentials = InMemoryRequestCredentials()
        let store = SessionStore(onChange: { SharedLayer.mirror($0, into: credentials) })
        #expect(credentials.authTokens == nil)

        await store.signIn(AuthCredentials(accessToken: "access-1", refreshToken: nil, userID: nil, uniqueUserID: nil, email: nil, phone: nil, firstName: nil, isGuest: false))
        await store.update { $0.geoToken = "geo-1" }
        #expect(credentials.authTokens?.accessToken == "access-1")
        #expect(credentials.geoToken == "geo-1")

        await store.signOut()
        #expect(credentials.authTokens == nil)
        // The geo token belongs to the device, not the account.
        #expect(credentials.geoToken == "geo-1")
    }

    @Test func aRestoredSessionIsMirroredAtLaunch() {
        let credentials = InMemoryRequestCredentials()
        let saved = InMemoryCredentialStore(AuthCredentials(accessToken: "saved-1", refreshToken: nil, userID: nil, uniqueUserID: nil, email: nil, phone: nil, firstName: nil, isGuest: false))

        _ = SessionStore(credentials: saved, onChange: { SharedLayer.mirror($0, into: credentials) })

        #expect(credentials.authTokens?.accessToken == "saved-1")
    }

    @Test func theAppUsesTheSharedAuthService() {
        #expect(AuthServices.live() is SharedAuthService)
    }

    @Test func sharedEncryptionDecryptsWithTheNativeImplementation() throws {
        let graph = SharedLayer.makeGraph(transportKey: "unit-test-passphrase")
        let plain = #"{"email":"user@example.com"}"#

        let cipher = try #require(graph.encryptForTransport(plainJson: plain))

        #expect(try CryptoJSAES.decrypt(cipher, passphrase: "unit-test-passphrase") == plain)
    }

    @Test func sharedClientSendsTheSameHeadersAsRequestHeaders() async throws {
        SharedStubURLProtocol.reset()

        // Native stack: APIClient + RequestHeaders, signed in with a profile and a geo token.
        let store = SessionStore()
        await store.update {
            $0.accessToken = "access-abc"
            $0.profileID = "profile-1"
            $0.geoToken = "geo-xyz"
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SharedStubURLProtocol.self]
        let native = APIClient(
            environment: .development,
            session: URLSession(configuration: configuration),
            headers: RequestHeaders(session: store, deviceID: "test-device", appVersion: "9.9.9", languageCode: { "ar" })
        )
        _ = try await native.get(Endpoint(path: "mediaview/api/v1/home"), as: IgnoredPayload.self)

        // Shared stack: the same values through the Kotlin header plugin on the Darwin engine.
        // The credentials come from the same session snapshot, as `SessionStore.shared` mirrors it.
        let credentials = InMemoryRequestCredentials()
        SharedLayer.mirror(await store.current(), into: credentials)
        let graph = SharedLayer.makeGraph(
            environment: .development,
            appVersion: "9.9.9",
            transportKey: "",
            deviceInfo: IOSSharedDeviceInfo(deviceId: "test-device", deviceName: "iPhone17,3", languageCode: { "ar" }),
            requestCredentials: credentials,
            engineFactory: {
                HttpEngine_appleKt.createDarwinEngine { $0.protocolClasses = [SharedStubURLProtocol.self] }
            }
        )
        let result = try await graph.apiCaller.get(path: "mediaview/api/v1/home", query: [], options: RequestOptions(sendGeoToken: true, redact: false))
        #expect(result is DataResultSuccess<AnyObject>)

        let requests = SharedStubURLProtocol.captured
        try #require(requests.count == 2)
        let (nativeRequest, sharedRequest) = (requests[0], requests[1])
        #expect(nativeRequest.url == sharedRequest.url)
        for name in Self.backendHeaders {
            #expect(nativeRequest.value(forHTTPHeaderField: name) == sharedRequest.value(forHTTPHeaderField: name), "\(name)")
        }
        #expect(sharedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-abc")
        #expect(sharedRequest.value(forHTTPHeaderField: "device_type") == "ios")
    }
}
#endif
