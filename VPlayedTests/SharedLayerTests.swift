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

/// The Kotlin Multiplatform shared layer, as the app builds it.
@MainActor
@Suite(.serialized)
struct SharedLayerTests {
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

    @Test func theAppSessionIsTheSharedSessionManager() async {
        #expect(SharedLayer.graph.sessionManager === SharedLayer.sessions)
    }

    @Test func theAppUsesTheSharedAuthService() {
        #expect(AuthServices.live() is SharedAuthService)
    }

    @Test func backendRequestsCarryTheAppHeadersOnTheDarwinEngine() async throws {
        SharedStubURLProtocol.reset()
        let sessions = SessionManager(store: InMemorySecureStore())
        try await sessions.signIn(session: AuthSession(AuthCredentials(accessToken: "access-abc", refreshToken: nil, userID: nil, uniqueUserID: nil, email: nil, phone: nil, firstName: nil, isGuest: false, profileID: "profile-1")))
        let graph = SharedLayer.makeGraph(
            environment: .development,
            appVersion: "9.9.9",
            transportKey: "",
            deviceInfo: IOSSharedDeviceInfo(deviceId: "test-device", deviceName: "iPhone17,3", languageCode: { "ar" }),
            sessions: sessions,
            engineFactory: {
                HttpEngine_appleKt.createDarwinEngine { $0.protocolClasses = [SharedStubURLProtocol.self] }
            }
        )
        // The shared geo lookup fills the graph's `GeoStore` in the app.
        graph.geoStore.updateGeo(token: "geo-xyz", info: nil)

        let result = try await graph.apiCaller.get(path: "mediaview/api/v1/home", query: [], options: RequestOptions(sendGeoToken: true, redact: false, endsSessionOnUnauthorized: true))

        #expect(result is DataResultSuccess<AnyObject>)
        #expect(SharedStubURLProtocol.captured.count == 1)
        let request = try #require(SharedStubURLProtocol.captured.first)
        #expect(request.url?.absoluteString == "https://api-devgs.vplayed.com/mediaview/api/v1/home")
        let expected = [
            "Accept": "application/json", "X-Request-Type": "mobile", "device_type": "ios", "app_version": "9.9.9",
            "X-Language-Code": "ar", "device_id": "test-device", "Authorization": "Bearer access-abc",
            "profile_id": "profile-1", "X-Bearer-Token": "geo-xyz",
        ]
        for (name, value) in expected {
            #expect(request.value(forHTTPHeaderField: name) == value, "\(name)")
        }
    }
}
