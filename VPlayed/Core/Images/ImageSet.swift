import Foundation

/// Size variants returned by the API, e.g. `new_thumbnail_images.default.tc`.
/// The codes describe sizes, not shapes. Measured on the dev and QA CDNs:
/// - Videos, series, promos and live (16:9): `tc` ≈ 1280–1567 px wide, the sharpest sensible size;
///   `tl` / `to` reach 1920–3840 px, `tv` ≈ 889, `tp` 420, `tm` 300.
/// - Micro-series (portrait): `tp` / `to` 700×922 (3:4) are the largest, `tl` 524×932 (9:16),
///   `tm` 340×450, and `tc` / `tv` only 231×307.
/// - `web` / `Key` sets (banners, posters, 2:3 thumbnails): `web` = `Key` is the full size, `mobile` smaller.
nonisolated enum ImageVariant: String, Sendable {
    case tv, tp, tm, tl, tc, to, ts, ta
    case mobile, web
    case key = "Key"
}

/// `{ "webp": { "tv": "path", … }, "default": { … }, "avif": null }` image sets.
nonisolated struct ImageSet: Decodable, Sendable, Hashable {
    /// format → variant → relative CDN path
    let formats: [String: [String: String]]

    /// The JPEG/PNG originals first: at the same pixel size the WebP copies are compressed much
    /// harder (often a third of the bytes) and look visibly softer. WebP is the fallback.
    /// AVIF is skipped: it is the largest decode cost and not needed for parity.
    private static let formatPreference = ["default", "webp"]

    init(formats: [String: [String: String]]) {
        self.formats = formats
    }

    init(from decoder: any Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode([String: [String: String?]?].self)) ?? [:]
        formats = raw.compactMapValues { variants in
            variants?.compactMapValues { path in
                guard let path, !path.isEmpty else { return nil }
                return path
            }
        }
    }

    /// The first available path, trying variants in order and formats in preference order.
    func path(preferring variants: [ImageVariant]) -> String? {
        for variant in variants {
            for format in Self.formatPreference {
                if let path = formats[format]?[variant.rawValue] {
                    return path
                }
            }
        }
        return nil
    }
}

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
