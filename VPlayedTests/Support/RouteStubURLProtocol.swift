import Foundation

/// A scripted backend that answers by host, path and `page` query, for code that sends requests
/// in parallel (Home loads banners and rails together). Its own state, so suites using
/// `AuthStubURLProtocol` never share it; suites using it are serialized.
final class RouteStubURLProtocol: URLProtocol {
    enum Answer {
        case json(status: Int, body: String)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: Answer] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    /// Routes are `host/path`, plus `?page=N` when the request has a page (e.g. `api-devgs.vplayed.com/mediaview/api/v1/home?page=2`).
    static func reset(_ scripted: [String: Answer] = [:]) { lock.withLock { routes = scripted; requests = [] } }

    static func set(_ route: String, _ answer: Answer) { lock.withLock { routes[route] = answer } }

    static var captured: [URLRequest] { lock.withLock { requests } }

    static func route(of url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let page = components?.queryItems?.first { $0.name == "page" }?.value
        return (url.host() ?? "") + url.path() + (page.map { "?page=\($0)" } ?? "")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let answer: Answer? = Self.lock.withLock {
            Self.requests.append(request)
            return Self.routes[Self.route(of: request.url!)]
        }
        switch answer ?? .json(status: 404, body: #"{"statusCode":404,"message":"No route"}"#) {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .json(let status, let body):
            let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
