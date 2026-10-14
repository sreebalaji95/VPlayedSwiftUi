import Foundation
import os

/// The `{statusCode, message, response}` envelope every VPlayed API returns.
nonisolated struct APIEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let statusCode: Int?
    let message: String?
    let response: Payload?
}

/// The outcome of a request that accepts more than one success code.
nonisolated struct APIResult<Payload: Sendable>: Sendable {
    let statusCode: Int
    let message: String?
    let payload: Payload?
}

/// A payload whose content is ignored; decodes from any JSON value.
nonisolated struct IgnoredPayload: Decodable, Sendable {
    init(from decoder: any Decoder) throws {}
}

/// An empty JSON object, for POSTs without parameters.
nonisolated struct EmptyBody: Encodable, Sendable {}

/// Status-only view of the envelope, decoded first so API errors survive payload-shape changes.
private nonisolated struct EnvelopeStatus: Decodable {
    let statusCode: Int?
    let message: String?
}

/// Async JSON client for the VPlayed REST API. Requests run off the main actor.
nonisolated final class APIClient: Sendable {
    static let shared = APIClient()

    private let environment: APIEnvironment
    private let session: URLSession
    private let headers: RequestHeaders
    private static let log = Logger(subsystem: "com.contus.vplayed", category: "API")

    init(
        environment: APIEnvironment = .current,
        session: URLSession = APIClient.makeSession(),
        headers: RequestHeaders = RequestHeaders()
    ) {
        self.environment = environment
        self.session = session
        self.headers = headers
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 32 << 20)
        return URLSession(configuration: configuration)
    }

    /// Performs a GET and returns the envelope's `response` payload.
    /// Success is decided by the envelope `statusCode == 200`, as in the UIKit app.
    @concurrent
    func get<Payload: Decodable & Sendable>(_ endpoint: Endpoint, as _: Payload.Type = Payload.self) async throws -> Payload {
        let request = try await makeRequest(endpoint, method: "GET", body: nil)
        let result = try await perform(request, path: endpoint.path, accepting: [200], as: Payload.self)
        guard let payload = result.payload else { throw APIError.decoding("Missing `response` payload") }
        return payload
    }

    /// Performs a JSON POST. Some auth endpoints answer with several success codes (the UIKit
    /// app accepts 200–203 there and branches on them), so the caller lists the codes it handles
    /// and gets the code back with the message and the optional payload.
    @concurrent
    func post<Body: Encodable & Sendable, Payload: Decodable & Sendable>(
        _ endpoint: Endpoint,
        body: Body,
        as _: Payload.Type = Payload.self,
        accepting codes: Set<Int> = [200]
    ) async throws -> APIResult<Payload> {
        let data: Data
        do {
            data = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decoding("Request body: \(error)")
        }
        let request = try await makeRequest(endpoint, method: "POST", body: data)
        return try await perform(request, path: endpoint.path, accepting: codes, as: Payload.self)
    }

    private func makeRequest(_ endpoint: Endpoint, method: String, body: Data?) async throws -> URLRequest {
        var request = URLRequest(url: try endpoint.url(relativeTo: environment.apiBaseURL))
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in await headers.values() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func perform<Payload: Decodable & Sendable>(
        _ request: URLRequest,
        path: String,
        accepting codes: Set<Int>,
        as _: Payload.Type
    ) async throws -> APIResult<Payload> {
        let method = request.httpMethod ?? "GET"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            Self.log.error("\(method, privacy: .public) \(path, privacy: .public) failed: URLError \(error.code.rawValue)")
            throw APIError.network(code: error.code.rawValue)
        }
        try Task.checkCancellation()

        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoder = JSONDecoder()
        guard let status = try? decoder.decode(EnvelopeStatus.self, from: data) else {
            Self.log.error("\(method, privacy: .public) \(path, privacy: .public) returned HTTP \(httpStatus) without a JSON envelope")
            throw [401, 403].contains(httpStatus) ? APIError.unauthorized : APIError.http(statusCode: httpStatus)
        }

        // Decision D1 (shared with Android): an HTTP error status always fails; within 2xx the
        // envelope's `statusCode` decides when present.
        let code = (200..<300).contains(httpStatus) ? status.statusCode ?? httpStatus : httpStatus
        guard codes.contains(code) else {
            if [401, 403].contains(code) { throw APIError.unauthorized }
            Self.log.error("\(method, privacy: .public) \(path, privacy: .public) API status \(code)")
            throw APIError.api(statusCode: code, message: status.message)
        }

        do {
            let payload = try decoder.decode(APIEnvelope<Payload>.self, from: data).response
            return APIResult(statusCode: code, message: status.message, payload: payload)
        } catch {
            Self.log.error("\(method, privacy: .public) \(path, privacy: .public) decoding failed: \(String(describing: error), privacy: .public)")
            throw APIError.decoding(String(describing: error))
        }
    }
}
