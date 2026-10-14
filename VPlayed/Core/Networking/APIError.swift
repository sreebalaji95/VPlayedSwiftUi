import Foundation

/// Failures the screens explain to the user. The shared layer's `AppError`s arrive here through
/// `APIError(_:)` (`SharedAuthService.swift`); `userMessage` stays native for localization.
nonisolated enum APIError: Error, Sendable, Equatable {
    /// Transport failure (offline, timeout, TLS…).
    case network(code: Int)
    /// The envelope's `statusCode` was not 200.
    case api(statusCode: Int, message: String?)
    /// 401/403 — the session is missing or expired.
    case unauthorized
    case decoding(String)

    var userMessage: String {
        switch self {
        case .network(let code) where code == URLError.notConnectedToInternet.rawValue
            || code == URLError.networkConnectionLost.rawValue:
            String(localized: "You appear to be offline. Check your connection and try again.", bundle: .localized)
        case .network(let code) where code == URLError.timedOut.rawValue:
            String(localized: "The server took too long to respond. Please try again.", bundle: .localized)
        case .network:
            String(localized: "We couldn't reach \(Brand.name). Please try again.", bundle: .localized)
        case .api(_, let message?) where !message.isEmpty:
            message
        case .unauthorized:
            String(localized: "Your session has expired. Please sign in again.", bundle: .localized)
        case .api, .decoding:
            String(localized: "Something went wrong while loading. Please try again.", bundle: .localized)
        }
    }
}
