import Darwin
import Foundation

/// What happened after asking for a sign-in code.
nonisolated enum SendCodeOutcome: Equatable, Sendable {
    /// A code is on its way: `statusCode` 200 (existing account) or 203 (new account). Both go to
    /// the code step (decision D2, as on Android; the UIKit app stopped at 203).
    case sent
    /// The account is signed in on its maximum number of devices (`statusCode` 202, decision D3).
    /// Signing other devices out here is Android-only until the backend confirms it is safe (D5).
    case deviceLimit(message: String?)
}

/// What happened after submitting the code.
nonisolated enum VerifyOutcome: Equatable, Sendable {
    /// `statusCode` 200, or 203 for a new account, with an access token (decision D4).
    case signedIn(AuthCredentials)
    /// The account is signed in on its maximum number of devices (`statusCode` 202), with the
    /// server's explanation. UIKit opens its sign-out-devices screen here.
    case deviceLimit(message: String?)
    /// `statusCode` 203 without a session: the account still needs registering.
    case newAccount
}

/// The UIKit app's passwordless email sign-in, guest login and logout.
nonisolated protocol AuthServicing: Sendable {
    func sendEmailCode(to email: String) async throws -> SendCodeOutcome
    func verifyEmailCode(_ code: String, email: String) async throws -> VerifyOutcome
    func guestLogin() async throws -> AuthCredentials
    func logout() async throws
}

/// The implementation the app uses: the Kotlin Multiplatform shared layer (`SharedAuthService`,
/// decisions D1–D4 in `KMP_PLANNING/KMP_ARCHITECTURE_ANALYSIS.md`). Tests pass mocks.
nonisolated enum AuthServices {
    static func live() -> any AuthServicing {
        SharedAuthService()
    }
}

/// The hardware model identifier (e.g. `iPhone17,3`, `Mac14,2`), sent as `deviceDetail`.
/// The UIKit app maps identifiers to marketing names first (`UIDevice.modelName`).
nonisolated enum DeviceModel {
    static let identifier: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()
}
