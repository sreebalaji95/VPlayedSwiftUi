import Foundation

/// A signed-in or guest session, as the UIKit app stores it after login
/// (`UIViewController.storeTokensUserDefaults`). Persisted by the shared `SessionManager` (iOS,
/// macOS) or by `CredentialStore` (visionOS); the shared layer reads both stored forms.
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

/// The `response` of the login endpoints (`auth/verifyEmailOtp`, `auth/generate`).
nonisolated struct AuthResponse: Decodable, Sendable {
    /// `nil` when the response carries no access token, so no session can be made from it.
    let credentials: AuthCredentials?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case id = "_id"
        case uniqueUserID = "unique_user_id"
        case guestUserID = "guest_user_id"
        case email
        case phone
        case firstName = "first_name"
        case isGuestUser = "is_guest_user"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isGuest = container.lenientBool(.isGuestUser) ?? false
        if let token = container.lenientString(.accessToken) {
            credentials = AuthCredentials(
                accessToken: token,
                refreshToken: container.lenientString(.refreshToken),
                userID: container.lenientString(.id),
                // Guests are identified by `guest_user_id`, falling back to `unique_user_id`.
                uniqueUserID: isGuest
                    ? container.lenientInt(.guestUserID) ?? container.lenientInt(.uniqueUserID)
                    : container.lenientInt(.uniqueUserID),
                email: container.lenientString(.email),
                phone: container.lenientString(.phone),
                firstName: container.lenientString(.firstName),
                isGuest: isGuest
            )
        } else {
            credentials = nil
        }
    }
}
