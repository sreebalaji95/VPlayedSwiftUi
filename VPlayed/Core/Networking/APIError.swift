import Foundation

nonisolated enum APIError: Error, Sendable, Equatable {
    case invalidURL
    /// Transport failure (offline, timeout, TLS…).
    case network(code: Int)
    /// Non-2xx HTTP status without a decodable API envelope.
    case http(statusCode: Int)
    /// The envelope's `statusCode` was not 200.
    case api(statusCode: Int, message: String?)
    /// 401/403 — the session is missing or expired.
    case unauthorized
    case decoding(String)

    var userMessage: String {
        switch self {
        case .network(let code) where code == URLError.notConnectedToInternet.rawValue
            || code == URLError.networkConnectionLost.rawValue:
            "You appear to be offline. Check your connection and try again."
        case .network(let code) where code == URLError.timedOut.rawValue:
            "The server took too long to respond. Please try again."
        case .network:
            "We couldn't reach VPlayed. Please try again."
        case .api(_, let message?) where !message.isEmpty:
            message
        case .unauthorized:
            "Your session has expired. Please sign in again."
        case .invalidURL, .http, .api, .decoding:
            "Something went wrong while loading. Please try again."
        }
    }
}
