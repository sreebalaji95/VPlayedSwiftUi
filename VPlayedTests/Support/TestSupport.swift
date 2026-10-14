import Foundation
@testable import VPlayed

private final class BundleToken {}

enum Fixture {
    /// Loads a JSON fixture captured from the dev API (`VPlayedTests/Fixtures`), served to the shared
    /// layer by `RouteStubURLProtocol`.
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}

/// A card item for view and model tests (the shared layer maps real ones; see `HomeFixtureTests`).
func makeItem(id: String = "item", shoType: Int? = 1, accessTag: AccessTag? = nil) -> ContentItem {
    ContentItem(id: id, title: "Title \(id)", shoType: shoType, accessTag: accessTag)
}
