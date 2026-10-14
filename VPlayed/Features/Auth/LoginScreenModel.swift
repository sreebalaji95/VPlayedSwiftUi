import Foundation
import Observation

/// The Login screen's steps.
enum LoginStep: Equatable {
    case email
    case code
    /// The account is signed in on its maximum number of devices: sign one out to continue.
    case devices
    /// Signed in; the screen shows "You're all set" and closes itself.
    case done
}

/// One device in the device-limit step.
struct LoginDevice: Identifiable, Equatable {
    enum Kind { case desktop, phone, tv, other }

    let id: String
    let name: String
    let kind: Kind
    /// Browser or app name, when the backend gives one.
    let detail: String?
    let isCurrent: Bool
}

/// What `LoginView` shows and calls. Two implementations: `SharedLoginViewModel` (iOS, macOS) runs
/// on the Kotlin shared controllers; `LoginViewModel` is the Swift version for visionOS, which has
/// no Kotlin/Native target. Both follow the same sign-in rules.
protocol LoginScreenModel: AnyObject, Observable {
    var step: LoginStep { get }
    var email: String { get set }
    var emailError: String? { get }
    /// Digits only, at most six.
    var code: String { get set }
    /// The address the code was sent to.
    var sentTo: String { get }
    /// Seconds until "Resend" is available again.
    var resendSeconds: Int { get }
    var isSending: Bool { get }
    var isVerifying: Bool { get }
    var isJoiningAsGuest: Bool { get }
    /// A session has started and the success step (if any) is over: the screen closes.
    var isFinished: Bool { get }
    /// An error to show above the form (server messages, connection problems).
    var notice: String? { get }
    /// A line under "You're all set" (profile setup or choice is not built yet).
    var doneNotice: String? { get }
    var canVerify: Bool { get }

    var devices: [LoginDevice] { get }
    var maxDevices: Int? { get }
    var isSigningOut: Bool { get }
    var hasSignedOutDevice: Bool { get }

    func continueWithEmail() async
    func continueAsGuest() async
    func verify() async
    func resend() async
    /// "Back" and "Change": return to the email step to fix the address.
    func editEmail()
    func stopTimers()

    func signOut(_ device: LoginDevice)
    func signOutAllDevices()
    func continueAfterSignOut()
}

/// The device-limit step exists only on the shared implementation.
extension LoginScreenModel {
    var doneNotice: String? { nil }
    var devices: [LoginDevice] { [] }
    var maxDevices: Int? { nil }
    var isSigningOut: Bool { false }
    var hasSignedOutDevice: Bool { false }

    func signOut(_ device: LoginDevice) {}
    func signOutAllDevices() {}
    func continueAfterSignOut() {}
}

/// Sign-in switches for this app.
enum AuthFeatures {
    /// The device-limit step (sign other devices out, then continue). Its "continue" signs in
    /// without a code (`verifyEmailLogin`), so it stays off until the backend confirms that is
    /// safe (decision D5); a device-limit answer shows the server's message instead.
    static let deviceSignOut = false
}
