import Foundation
@testable import VPlayed

private final class BundleToken {}

enum Fixture {
    /// Loads a JSON fixture captured from the dev API (`VPlayedTests/Fixtures`).
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    /// Decodes a fixture's envelope `response` payload.
    static func payload<T: Decodable & Sendable>(_ name: String, as _: T.Type) throws -> T {
        let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data(name))
        guard let response = envelope.response else { throw FixtureError.missing("\(name).response") }
        return response
    }

    enum FixtureError: Error {
        case missing(String)
    }
}

extension HomeSection {
    /// Builds a section from inline JSON for focused decoding tests.
    static func decode(_ json: String) throws -> HomeSection {
        try JSONDecoder().decode(HomeSection.self, from: Data(json.utf8))
    }
}

func makeItem(
    id: String = "item",
    monetization: Int? = nil,
    prices: [[String: Any]] = [],
    isSubscription: Bool? = nil,
    isUserSubscribed: Bool? = nil,
    scheduled: Bool? = nil,
    shoType: Any? = 1
) throws -> ContentItem {
    var object: [String: Any] = ["_id": id, "title": "Title \(id)", "prices": prices]
    if let monetization { object["monetization"] = monetization }
    if let isSubscription { object["is_subscription"] = isSubscription }
    if let isUserSubscribed { object["is_user_subscribed"] = isUserSubscribed }
    if let scheduled { object["scheduled"] = scheduled }
    if let shoType { object["sho_type"] = shoType }
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(ContentItem.self, from: data)
}
