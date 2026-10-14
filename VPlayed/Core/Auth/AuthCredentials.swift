import Foundation

/// A signed-in or guest session, as the UIKit app stores it after login
/// (`UIViewController.storeTokensUserDefaults`). Persisted by the shared `SessionManager`, which also
/// reads sessions stored in this form before it (Phase 5).
nonisolated struct AuthCredentials: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var userID: String?
    var uniqueUserID: Int?
    var email: String?
    var phone: String?
    var firstName: String?
    var isGuest: Bool
    /// The default profile's id, sent as `profile_id` (set by the shared sign-in; nil in sessions
    /// stored before it, which decode as before).
    var profileID: String? = nil

    /// What Menu shows for the account: the first name, else the email, else the phone number.
    var displayName: String? { firstName ?? email ?? phone }
}
