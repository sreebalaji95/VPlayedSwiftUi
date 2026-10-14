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

/// The implementation the app uses: the Kotlin Multiplatform shared layer where it links (iOS,
/// macOS), the Swift `AuthService` on visionOS, which has no Kotlin/Native target. Both follow
/// the same rules (decisions D1–D4 in `KMP_PLANNING/KMP_ARCHITECTURE_ANALYSIS.md`).
nonisolated enum AuthServices {
    static func live() -> any AuthServicing {
        #if canImport(Shared)
        SharedAuthService()
        #else
        AuthService()
        #endif
    }
}

/// The Swift implementation, used on visionOS (see `AuthServices.live()`); replaced by
/// `SharedAuthService` elsewhere and removed once visionOS is settled (Phase 7).
nonisolated struct AuthService: AuthServicing {
    var client: APIClient = .shared
    var deviceID: String = DeviceID.current
    var deviceName: String = DeviceModel.identifier

    private struct EncryptedBody: Encodable, Sendable {
        let data: String
    }

    private struct GuestBody: Encodable, Sendable {
        let uuid: String
    }

    /// `LoginViewController.sendOtpToMail` / `getEmailEncrypted`.
    func sendEmailCode(to email: String) async throws -> SendCodeOutcome {
        let body = try encrypted(["email": email])
        let result = try await client.post(.emailLogin, body: body, as: IgnoredPayload.self, accepting: [200, 202, 203])
        return result.statusCode == 202 ? .deviceLimit(message: result.message) : .sent
    }

    /// `OtpViewController.verifyMailOtp` / `getOtpEncrypted`.
    func verifyEmailCode(_ code: String, email: String) async throws -> VerifyOutcome {
        let body = try encrypted(["email": email, "otp": code, "deviceDetail": deviceName])
        let result = try await client.post(.verifyEmailOTP, body: body, as: AuthResponse.self, accepting: [200, 202, 203])
        if result.statusCode == 202 {
            return .deviceLimit(message: result.message)
        }
        if let credentials = result.payload?.credentials {
            return .signedIn(credentials)
        }
        if result.statusCode == 203 { return .newAccount }
        throw APIError.decoding("No access token")
    }

    /// `ProfileTabViewModel.guestUserLogin`.
    func guestLogin() async throws -> AuthCredentials {
        let result = try await client.post(.guestLogin, body: GuestBody(uuid: deviceID), as: AuthResponse.self)
        guard var credentials = result.payload?.credentials else { throw APIError.decoding("No access token") }
        // This endpoint only issues guest sessions, whatever `is_guest_user` says.
        credentials.isGuest = true
        return credentials
    }

    /// `ProfileTabViewModel.logout`. The UIKit repository accepts 200–203 for auth calls.
    func logout() async throws {
        _ = try await client.post(.logout, body: EmptyBody(), as: IgnoredPayload.self, accepting: [200, 201, 202, 203])
    }

    private func encrypted(_ fields: [String: String]) throws -> EncryptedBody {
        let json = try JSONSerialization.data(withJSONObject: fields, options: [.withoutEscapingSlashes])
        return EncryptedBody(data: try CryptoJSAES.encrypt(String(decoding: json, as: UTF8.self), passphrase: CryptoJSAES.authPassphrase))
    }
}

/// The hardware model identifier (e.g. `iPhone17,3`, `Mac14,2`), sent as `deviceDetail`.
/// The UIKit app maps identifiers to marketing names first (`UIDevice.modelName`).
nonisolated enum DeviceModel {
    static let identifier: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #else
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #endif
    }()
}
