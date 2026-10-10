import Foundation
import os

/// The `{statusCode, message, response}` envelope every VPlayed API returns.
nonisolated struct APIEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let statusCode: Int?
    let message: String?
    let response: Payload?
}

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
        var request = URLRequest(url: try endpoint.url(relativeTo: environment.apiBaseURL))
        request.httpMethod = "GET"
        for (name, value) in await headers.values() {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            Self.log.error("GET \(endpoint.path, privacy: .public) failed: URLError \(error.code.rawValue)")
            throw APIError.network(code: error.code.rawValue)
        }
        try Task.checkCancellation()

        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoder = JSONDecoder()
        guard let status = try? decoder.decode(EnvelopeStatus.self, from: data) else {
            Self.log.error("GET \(endpoint.path, privacy: .public) returned HTTP \(httpStatus) without a JSON envelope")
            throw [401, 403].contains(httpStatus) ? APIError.unauthorized : APIError.http(statusCode: httpStatus)
        }

        switch status.statusCode ?? httpStatus {
        case 200:
            break
        case 401, 403:
            throw APIError.unauthorized
        case let code:
            Self.log.error("GET \(endpoint.path, privacy: .public) API status \(code)")
            throw APIError.api(statusCode: code, message: status.message)
        }

        do {
            guard let payload = try decoder.decode(APIEnvelope<Payload>.self, from: data).response else {
                throw APIError.decoding("Missing `response` payload")
            }
            return payload
        } catch let error as APIError {
            throw error
        } catch {
            Self.log.error("GET \(endpoint.path, privacy: .public) decoding failed: \(String(describing: error), privacy: .public)")
            throw APIError.decoding(String(describing: error))
        }
    }
}
