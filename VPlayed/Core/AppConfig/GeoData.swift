import Foundation

/// The `response` of `GET mediaview/api/v1/common/geo-data/{ip}`. The token is `null` when the
/// server can't place the address.
nonisolated struct GeoTokenResponse: Decodable, Sendable {
    var geoToken: String?

    private enum CodingKeys: String, CodingKey {
        case geoToken = "geo_token"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        geoToken = container.lenientString(.geoToken)
    }
}

/// The location inside a geo token, which is base64-encoded JSON
/// (decoded the same way as `RegisterViewController.getCoinsPlansClaimsCheck` in the UIKit app).
nonisolated struct GeoInfo: Decodable, Sendable, Equatable {
    var country: String?
    var countryCode: String?
    var currency: String?
    var region: String?
    var regionName: String?
    var city: String?
    var timezone: String?

    private enum CodingKeys: String, CodingKey {
        case country, countryCode, currency, region, regionName, city, timezone
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        country = container.lenientString(.country)
        countryCode = container.lenientString(.countryCode)
        currency = container.lenientString(.currency)
        region = container.lenientString(.region)
        regionName = container.lenientString(.regionName)
        city = container.lenientString(.city)
        timezone = container.lenientString(.timezone)
    }

    /// Returns nil for a token that isn't base64-encoded JSON.
    init?(token: String) {
        guard let data = Data(base64Encoded: token),
              let info = try? JSONDecoder().decode(GeoInfo.self, from: data) else { return nil }
        self = info
    }
}
