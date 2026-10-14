#if canImport(Shared)
import Foundation
// Kotlin classes are not Sendable; the repository is thread-safe and only used through this adapter.
@preconcurrency import Shared

/// Sign-in through the Kotlin Multiplatform shared layer (`SharedGraph.authRepository`), the same
/// code AndroidJP uses: request encryption, endpoints and the status-code rules (decisions D1–D4).
/// This adapter only maps the shared results to the app's outcomes and `APIError`s, so
/// `LoginViewModel` and `AccountStore` are unchanged. Storing the session stays with `AccountStore`.
///
/// The device-limit sign-out (`signOutDevice`, `continueAfterDeviceSignOut`) is not offered on
/// iOS until the backend confirms that signing in without a code is safe (decision D5).
nonisolated final class SharedAuthService: AuthServicing, @unchecked Sendable {
    private let repository: AuthRepository

    init(graph: SharedGraph = SharedLayer.graph) {
        repository = graph.authRepository
    }

    func sendEmailCode(to email: String) async throws -> SendCodeOutcome {
        let result = try await repository.requestEmailLogin(email: email)
        switch result {
        case is EmailLoginResultCodeSent:
            return .sent
        case let limit as EmailLoginResultDeviceLimitReached:
            return .deviceLimit(message: limit.message)
        case let rejected as EmailLoginResultRejected:
            throw APIError.rejected(rejected.message)
        case let failure as EmailLoginResultFailure:
            throw APIError(failure.error)
        default:
            throw APIError.decoding("Unknown email-login result")
        }
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> VerifyOutcome {
        let result = try await repository.verifyEmailOtp(email: email, code: code)
        switch result {
        case let verified as OtpVerificationResultVerified:
            return .signedIn(AuthCredentials(verified.session))
        case is OtpVerificationResultRegistrationRequired:
            return .newAccount
        case let limit as OtpVerificationResultDeviceLimitReached:
            return .deviceLimit(message: limit.message)
        case let rejected as OtpVerificationResultRejected:
            throw APIError.rejected(rejected.message)
        case let failure as OtpVerificationResultFailure:
            throw APIError(failure.error)
        default:
            throw APIError.decoding("Unknown verification result")
        }
    }

    func guestLogin() async throws -> AuthCredentials {
        let result = try await repository.guestLogin()
        switch result {
        case let signedIn as GuestLoginResultSignedIn:
            return AuthCredentials(signedIn.session)
        case let rejected as GuestLoginResultRejected:
            throw APIError.rejected(rejected.message)
        case let failure as GuestLoginResultFailure:
            throw APIError(failure.error)
        default:
            throw APIError.decoding("Unknown guest-login result")
        }
    }

    /// `AccountStore` forgets the session on success and on `APIError.unauthorized`.
    func logout() async throws {
        let result = try await repository.logout()
        switch result {
        case is LogoutResultLoggedOut:
            return
        case is LogoutResultSessionAlreadyEnded:
            throw APIError.unauthorized
        case let rejected as LogoutResultRejected:
            throw APIError.rejected(rejected.message)
        case let failure as LogoutResultFailure:
            throw APIError(failure.error)
        default:
            throw APIError.decoding("Unknown logout result")
        }
    }
}

extension AuthCredentials {
    nonisolated init(_ session: AuthSession) {
        self.init(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userID: session.userId,
            uniqueUserID: session.uniqueUserId.map { Int(truncating: $0) },
            email: session.email,
            phone: session.phone,
            firstName: session.firstName,
            isGuest: session.isGuest
        )
    }
}

extension APIError {
    /// A refusal the server explained (or not); shown like any API error message.
    nonisolated static func rejected(_ message: String?) -> APIError {
        .api(statusCode: 0, message: message)
    }

    /// The shared layer's failure, as the error the screens already explain.
    nonisolated init(_ error: any AppError) {
        switch error {
        case is AppErrorNetwork:
            // The shared layer does not say whether the device is offline: use the generic message.
            self = .network(code: URLError.Code.cannotConnectToHost.rawValue)
        case is AppErrorTimeout:
            self = .network(code: URLError.Code.timedOut.rawValue)
        case is AppErrorUnauthorized:
            self = .unauthorized
        case let server as AppErrorServer:
            self = .api(statusCode: Int(server.code), message: server.message)
        case let configuration as AppErrorConfiguration:
            self = .decoding(configuration.reason)
        default:
            // Parsing and unknown failures.
            self = .decoding(String(describing: error))
        }
    }
}
#endif
