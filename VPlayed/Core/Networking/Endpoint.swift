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

    /// Hero banners. `GET mediaview/api/v1/homebanners`
    static let homeBanners = Endpoint(path: mediaView + "homebanners")

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
}
