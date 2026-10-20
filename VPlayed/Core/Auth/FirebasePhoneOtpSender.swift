import Foundation
// Firebase and Kotlin types are not Sendable; results are handed straight back to Kotlin.
@preconcurrency import FirebaseAuth
@preconcurrency import Shared

/// The shared layer's `PhoneOtpSender` over Firebase Auth, as the UIKit app sends and checks phone
/// codes (`OTPViewModel.callPhoneAuthAPI` / `verifyPhoneAuthLogin`). The backend never sees the
/// code: once Firebase accepts it, the shared `OtpController` calls `auth/phone-login`.
///
/// Without APNs set up for Firebase, it verifies the app with a reCAPTCHA page that returns through
/// the `VPLAYED_FIREBASE_URL_SCHEME` URL scheme (`AuthURLHandler`). Unlike the UIKit app it never
/// disables app verification. Kotlin calls it from the main thread; every callback fires once.
nonisolated final class FirebasePhoneOtpSender: NSObject, PhoneOtpSender, @unchecked Sendable {
    static let shared = FirebasePhoneOtpSender()

    func sendCode(phoneNumber: String, onResult: @escaping (any PhoneCodeSendResult) -> Void) {
        let reply = UncheckedBox(onResult)
        guard FirebaseBootstrap.isPhoneSignInReady else {
            reply.value(PhoneCodeSendResultFailed(reason: .notConfigured))
            return
        }
        DispatchQueue.main.async {
            PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { verificationID, error in
                if let verificationID, error == nil {
                    reply.value(PhoneCodeSendResultCodeSent(verificationId: verificationID))
                } else {
                    reply.value(PhoneCodeSendResultFailed(reason: Self.failure(error)))
                }
            }
        }
    }

    func verifyCode(verificationId: String, code: String, onResult: @escaping (any PhoneCodeCheckResult) -> Void) {
        let reply = UncheckedBox(onResult)
        guard FirebaseBootstrap.isConfigured else {
            reply.value(PhoneCodeCheckResultFailed(reason: .notConfigured))
            return
        }
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationId, verificationCode: code)
        Auth.auth().signIn(with: credential) { _, error in
            guard let error else {
                // Only the check was needed; the backend session is the account's session.
                try? Auth.auth().signOut()
                reply.value(PhoneCodeCheckResultVerified.shared)
                return
            }
            if Self.isInvalidCode(error) {
                reply.value(PhoneCodeCheckResultInvalidCode.shared)
            } else {
                reply.value(PhoneCodeCheckResultFailed(reason: Self.failure(error)))
            }
        }
    }

    private static func isInvalidCode(_ error: any Error) -> Bool {
        let code = (error as NSError).code
        return [AuthErrorCode.invalidVerificationCode, .invalidVerificationID, .sessionExpired, .missingVerificationCode]
            .contains { $0.rawValue == code }
    }

    private static func failure(_ error: (any Error)?) -> PhoneCodeFailure {
        guard let error = error as NSError? else { return .other }
        switch AuthErrorCode(rawValue: error.code) {
        case .invalidPhoneNumber, .missingPhoneNumber: return .invalidNumber
        case .tooManyRequests, .quotaExceeded: return .tooManyRequests
        case .networkError: return .network
        default: return .other
        }
    }
}

/// Carries a non-Sendable value (a Kotlin callback) across Firebase's completion queues.
nonisolated struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
