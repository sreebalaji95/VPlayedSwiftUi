import Foundation

/// A signed-in or guest session, as the UIKit app stores it after login
/// (`UIViewController.storeTokensUserDefaults`). Persisted by `CredentialStore`.
nonisolated struct AuthCredentials: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var userID: String?
    var uniqueUserID: Int?
    var email: String?
    var phone: String?
    var firstName: String?
    var isGuest: Bool

    /// What Menu shows for the account: the first name, else the email, else the phone number.
    var displayName: String? { firstName ?? email ?? phone }
}

/// The `response` of the login endpoints (`auth/verifyEmailOtp`, `auth/generate`).
nonisolated struct AuthResponse: Decodable, Sendable {
    /// `nil` when the response carries no access token, so no session can be made from it.
    let credentials: AuthCredentials?
    /// The UIKit app sends a verified email with no phone and no Apple, Facebook or Google ID
    /// to the Register screen instead of signing it in (`OtpViewController.handleMailOtpStatus200`).
    let hasLinkedSignIn: Bool

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
        case appleAuthID = "apple_auth_id"
        case facebookAuthID = "facebook_auth_id"
        case googleAuthID = "google_auth_id"
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
        // Any string counts, even an empty one, as with SwiftyJSON's `.string` in the UIKit check.
        hasLinkedSignIn = [CodingKeys.phone, .appleAuthID, .facebookAuthID, .googleAuthID]
            .contains { ((try? container.decodeIfPresent(String.self, forKey: $0)) ?? nil) != nil }
    }
}
