import Foundation
// Kotlin classes are not Sendable; the repository is thread-safe and only used through this adapter.
@preconcurrency import Shared

/// One page of the movie catalogue.
nonisolated struct MediaPage: Sendable {
    let items: [ContentItem]
    /// Titles in the whole catalogue, e.g. 1,997.
    let total: Int?
    /// The next page number, or nil on the last page.
    let nextPage: Int?
}

/// Data source for the Movies screen.
nonisolated protocol MoviesServicing: Sendable {
    func page(_ page: Int) async throws -> MediaPage
}

/// The movie catalogue through the Kotlin shared layer (`SharedGraph.moviesRepository`,
/// `GET mediaview/api/v1/sho-details/media/1`). Items get the same image, price and access-tag rules
/// as Home (`SharedHomeMapping`); the paging rules stay in `MoviesViewModel`.
nonisolated final class SharedMoviesService: MoviesServicing, @unchecked Sendable {
    private let repository: MoviesRepository

    init(graph: SharedGraph = SharedLayer.graph) {
        repository = graph.moviesRepository
    }

    func page(_ page: Int) async throws -> MediaPage {
        let result = try await repository.getPage(page: Int32(page))
        switch result {
        case let success as DataResultSuccess<MoviesPage>:
            guard let page = success.data else { throw APIError.decoding("Empty movies page") }
            return MediaPage(
                items: page.items.map(SharedHomeMapping.contentItem),
                total: page.total.map { Int(truncating: $0) },
                nextPage: page.nextPage.map { Int(truncating: $0) }
            )
        case let failure as DataResultFailure:
            throw APIError(failure.error)
        default:
            throw APIError.decoding("Unknown movies result")
        }
    }
}
