import Foundation

/// The Login screen's steps.
enum LoginStep: Equatable {
    case email
    case code
    /// The account is signed in on its maximum number of devices: sign one out to continue.
    case devices
    /// A new account adds its name and its mobile number or email before it is signed in.
    case register
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

/// Sign-in switches for this app.
enum AuthFeatures {
    /// The device-limit step (sign other devices out, then continue). Its "continue" signs in
    /// without a code (`verifyEmailLogin`), so it stays off until the backend confirms that is
    /// safe (decision D5); a device-limit answer shows the server's message instead.
    static let deviceSignOut = false
}
