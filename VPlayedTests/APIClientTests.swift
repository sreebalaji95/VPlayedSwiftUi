import Foundation
import Testing
@testable import VPlayed

/// Serves canned responses to `APIClient` without touching the network.
final class StubURLProtocol: URLProtocol {
    struct Response: Sendable {
        var status: Int = 200
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var response = Response(body: Data())
    nonisolated(unsafe) private static var lastRequest: URLRequest?

    static func stub(_ response: Response) {
        lock.withLock {
            self.response = response
            lastRequest = nil
        }
    }

    static var capturedRequest: URLRequest? { lock.withLock { lastRequest } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.lock.withLock {
            Self.lastRequest = request
            return Self.response
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct APIClientTests {
    private func makeClient(session: SessionStore = SessionStore()) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            environment: .development,
            session: URLSession(configuration: configuration),
            headers: RequestHeaders(session: session, deviceID: "test-device", appVersion: "9.9.9", languageCode: { "en" })
        )
    }

    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func successReturnsPayloadAndBuildsRequest() async throws {
        StubURLProtocol.stub(.init(body: try Fixture.data("home-page-1")))

        let page = try await makeClient().get(.home(page: 1), as: HomeFeedPage.self)

        #expect(page.sections.count == 3)
        let request = try #require(StubURLProtocol.capturedRequest)
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.host == "api-devgs.vplayed.com")
        #expect(components.path == "/mediaview/api/v1/home")
        #expect(Set(components.queryItems ?? []) == [
            URLQueryItem(name: "limit", value: "3"),
            URLQueryItem(name: "inside_limit", value: "10"),
            URLQueryItem(name: "page", value: "1"),
        ])
        #expect(request.httpMethod == "GET")
    }

    @Test func sendsMobileHeadersWithoutCredentialsForGuests() async throws {
        StubURLProtocol.stub(.init(body: body(#"{"statusCode":200,"response":{"data":[]}}"#)))

        _ = try await makeClient().get(.homeBanners, as: HomeBannerList.self)

        let headers = try #require(StubURLProtocol.capturedRequest?.allHTTPHeaderFields)
        #expect(headers["X-Request-Type"] == "mobile")
        #expect(headers["device_type"] == "ios")
        #expect(headers["device_id"] == "test-device")
        #expect(headers["app_version"] == "9.9.9")
        #expect(headers["X-Language-Code"] == "en")
        #expect(headers["Authorization"] == nil)
        #expect(headers["profile_id"] == nil)
        #expect(headers["X-Bearer-Token"] == nil)
    }

    @Test func sendsCredentialsWhenTheSessionHasThem() async throws {
        let session = SessionStore()
        await session.update {
            $0.accessToken = "token"
            $0.profileID = "profile"
            $0.geoToken = "geo"
        }
        StubURLProtocol.stub(.init(body: body(#"{"statusCode":200,"response":{"data":[]}}"#)))

        _ = try await makeClient(session: session).get(.homeBanners, as: HomeBannerList.self)

        let headers = try #require(StubURLProtocol.capturedRequest?.allHTTPHeaderFields)
        #expect(headers["Authorization"] == "Bearer token")
        #expect(headers["profile_id"] == "profile")
        #expect(headers["X-Bearer-Token"] == "geo")
    }

    @Test func envelopeStatusCodeDrivesErrors() async throws {
        StubURLProtocol.stub(.init(status: 200, body: body(#"{"statusCode":422,"message":"Invalid page"}"#)))
        await #expect(throws: APIError.api(statusCode: 422, message: "Invalid page")) {
            try await makeClient().get(.home(page: 99), as: HomeFeedPage.self)
        }

        StubURLProtocol.stub(.init(status: 401, body: body(#"{"statusCode":401,"message":"Unauthorized"}"#)))
        await #expect(throws: APIError.unauthorized) {
            try await makeClient().get(.homeBanners, as: HomeBannerList.self)
        }
    }

    @Test func nonJSONResponsesSurfaceTheHTTPStatus() async throws {
        StubURLProtocol.stub(.init(status: 502, body: body("<html>Bad gateway</html>")))
        await #expect(throws: APIError.http(statusCode: 502)) {
            try await makeClient().get(.homeBanners, as: HomeBannerList.self)
        }
    }

    @Test func missingPayloadIsADecodingError() async throws {
        StubURLProtocol.stub(.init(body: body(#"{"statusCode":200,"message":"ok"}"#)))
        await #expect {
            try await makeClient().get(.homeBanners, as: HomeBannerList.self)
        } throws: { error in
            if case APIError.decoding = error { return true }
            return false
        }
    }
}
