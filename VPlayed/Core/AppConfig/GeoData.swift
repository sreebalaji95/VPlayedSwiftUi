import Foundation

/// The location inside a geo token, which is base64-encoded JSON
/// (decoded the same way as `RegisterViewController.getCoinsPlansClaimsCheck` in the UIKit app).
nonisolated struct GeoInfo: Sendable, Equatable {
    var country: String?
    var countryCode: String?
    var currency: String?
    var region: String?
    var regionName: String?
    var city: String?
    var timezone: String?

    init(
        country: String? = nil,
        countryCode: String? = nil,
        currency: String? = nil,
        region: String? = nil,
        regionName: String? = nil,
        city: String? = nil,
        timezone: String? = nil
    ) {
        self.country = country
        self.countryCode = countryCode
        self.currency = currency
        self.region = region
        self.regionName = regionName
        self.city = city
        self.timezone = timezone
    }

}

/// A geo token and the location it encodes (nil when the token isn't readable).
nonisolated struct GeoLookup: Sendable, Equatable {
    var token: String
    var info: GeoInfo?
}
