import Foundation

/// A GET request path relative to `APIEnvironment.apiBaseURL`.
nonisolated struct Endpoint: Sendable, Hashable {
    var path: String
    var queryItems: [URLQueryItem] = []

    func url(relativeTo baseURL: URL) throws(APIError) -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw .invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw .invalidURL }
        return url
    }
}

extension Endpoint {
    private static let mediaView = "mediaview/api/v1/"
    private static let users = "users/api/v1/"
    private static let studios = "studios/api/v1/"

    /// App-wide feature flags, payment switches and update settings, fetched at launch
    /// (`ProfileTabViewModel.getCommonKeys`). `GET mediaview/api/v1/common`
    static let common = Endpoint(path: mediaView + "common")

    /// The geo token for a public IP address, sent back as `X-Bearer-Token`
    /// (`ProfileRepository.getGeoRestrictToken`). `GET mediaview/api/v1/common/geo-data/{ip}`
    static func geoData(ip: String) -> Endpoint {
        Endpoint(path: mediaView + "common/geo-data/" + ip)
    }

    /// Hero banners. `GET mediaview/api/v1/homebanners`
    static let homeBanners = Endpoint(path: mediaView + "homebanners")

    /// Follows or unfollows a channel (`StudioRepository.studioFollowRequest`).
    /// `POST studios/api/v1/follow_studio` with `{"studio": slug, "follow": "1" | "0"}`.
    static let followChannel = Endpoint(path: studios + "follow_studio")

    /// Paged home rails, as requested by the iOS app (`ShocialViewModel.getHomeDynamicShocialListAPI`).
    /// `limit` is the number of rails per page; `insideLimit` the number of items per rail.
    static func home(page: Int, limit: Int = 3, insideLimit: Int = 10) -> Endpoint {
        Endpoint(
            path: mediaView + "home",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "inside_limit", value: String(insideLimit)),
                URLQueryItem(name: "page", value: String(page)),
            ]
        )
    }

    /// Paged catalogue of one content type, as the UIKit Movies / Micro-series screens request it
    /// (`HomeViewModel.getMoviesListAPI`). `shoType`: 1 movies, 2 series, 6 micro-series.
    /// `GET mediaview/api/v1/sho-details/media/{shoType}?page=&limit=&is_promo=true`
    static func media(shoType: Int, page: Int, limit: Int = 10) -> Endpoint {
        Endpoint(
            path: mediaView + "sho-details/media/\(shoType)",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "is_promo", value: "true"),
            ]
        )
    }

    // MARK: Auth (POST)

    /// Sends a sign-in code to an email address; the body is `{"data": <encrypted {"email"}>}`
    /// (`LoginViewModel.loginEmailViaOTP`). `POST users/api/v1/auth/email-login`
    static let emailLogin = Endpoint(path: users + "auth/email-login")

    /// Checks the emailed code; the body is `{"data": <encrypted {"email","otp","deviceDetail"}>}`
    /// (`LoginViewModel.verifyEmailViaOTP`). `POST users/api/v1/auth/verifyEmailOtp`
    static let verifyEmailOTP = Endpoint(path: users + "auth/verifyEmailOtp")

    /// Creates a guest session for this device; the body is `{"uuid": <device id>}`
    /// (`ProfileTabViewModel.guestUserLogin`). `POST users/api/v1/auth/generate`
    static let guestLogin = Endpoint(path: users + "auth/generate")

    /// Ends the signed-in session (`ProfileTabViewModel.logout`). `POST users/api/v1/auth/logout`
    static let logout = Endpoint(path: users + "auth/logout")
}
