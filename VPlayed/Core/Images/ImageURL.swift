import Foundation

nonisolated enum ImageURL {
    /// Resolves an API image value: absolute URLs pass through, relative keys are joined to the CDN.
    static func resolve(_ path: String?, imageBaseURL: URL = APIEnvironment.current.imageBaseURL) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
        }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: encoded, relativeTo: imageBaseURL)?.absoluteURL
    }
}
