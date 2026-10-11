import Foundation

/// One page of the `sho-details/media/{type}` catalogue.
nonisolated struct MediaPage: Decodable, Sendable {
    let items: [ContentItem]
    /// Titles in the whole catalogue, e.g. 1,997.
    let total: Int?
    /// The next page number, or nil on the last page.
    let nextPage: Int?

    private enum CodingKeys: String, CodingKey {
        case data, total, next
    }

    init(items: [ContentItem], total: Int?, nextPage: Int?) {
        self.items = items
        self.total = total
        self.nextPage = nextPage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = container.lossyArray(ContentItem.self, .data)
        total = container.lenientInt(.total)
        nextPage = container.lenientInt(.next).flatMap { $0 > 0 ? $0 : nil }
    }
}

/// Data source for the Movies screen.
nonisolated protocol MoviesServicing: Sendable {
    func page(_ page: Int) async throws -> MediaPage
}

nonisolated struct MoviesService: MoviesServicing {
    var client: APIClient = .shared

    func page(_ page: Int) async throws -> MediaPage {
        try await client.get(.media(shoType: 1, page: page), as: MediaPage.self)
    }
}
