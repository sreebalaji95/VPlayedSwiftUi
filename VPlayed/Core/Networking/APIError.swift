import Foundation

/// Failures the screens explain to the user. The shared layer's `AppError`s arrive here through
/// `APIError(_:)` (`SharedAuthService.swift`); `userMessage` reads the shared string catalog.
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
            L10n.string(.errorOffline)
        case .network(let code) where code == URLError.timedOut.rawValue:
            L10n.string(.errorTimeout)
        case .network:
            L10n.string(.errorUnreachable, [Brand.name])
        case .api(_, let message?) where !message.isEmpty:
            message
        case .unauthorized:
            L10n.string(.errorSessionExpired)
        case .api, .decoding:
            L10n.string(.errorGeneric)
        }
    }
}
