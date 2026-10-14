import Foundation
import SwiftUI
import Testing
@testable import VPlayed

/// Scripted `MoviesServicing` for ViewModel tests. Development-only; never used by the app.
final class MockMoviesService: MoviesServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var pages: [Int: Result<MediaPage, any Error>]
    private var calls: [Int] = []

    init(pages: [Int: Result<MediaPage, any Error>]) {
        self.pages = pages
    }

    var pageCalls: [Int] { lock.withLock { calls } }

    func setPage(_ page: Int, _ result: Result<MediaPage, any Error>) {
        lock.withLock { pages[page] = result }
    }

    func page(_ page: Int) async throws -> MediaPage {
        lock.withLock { calls.append(page) }
        guard let result = lock.withLock({ pages[page] }) else { throw APIError.api(statusCode: 404, message: nil) }
        return try result.get()
    }
}

private func movies(_ ids: [String], total: Int? = 100, next: Int?) throws -> MediaPage {
    MediaPage(items: ids.map { makeItem(id: $0) }, total: total, nextPage: next)
}

extension RoutedBackendTests {
    /// The dev-API movie page through the shared layer (`SharedMoviesService`), as the Movies tab reads it.
    @MainActor
    @Suite
    struct SharedMoviesServiceTests {
        private static let firstPage = RoutedBackend.route("mediaview/api/v1/sho-details/media/1", page: 1)

        @Test func readsTheMoviesPage() async throws {
            RouteStubURLProtocol.reset([Self.firstPage: try RoutedBackend.fixture("movies-page-1")])

            let page = try await SharedMoviesService(graph: RoutedBackend.graph()).page(1)

            #expect(page.items.count == 3)
            #expect(page.total == 1997)
            #expect(page.nextPage == 2)
            let first = try #require(page.items.first)
            #expect(first.title == "sample1")
            #expect(first.genre == "Comedy")
            #expect(first.landscapeImageURL != nil)
            // Every item carries `default_genre`, whether the full genre document or just _id/title/slug.
            #expect(page.items.map(\.genre) == ["Comedy", "Action", "Action"])
            let query = try #require(RouteStubURLProtocol.captured.first?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems)
            #expect(Set(query.map(\.name)) == ["page", "limit", "is_promo"])
        }

        @Test func failuresBecomeTheScreensErrors() async throws {
            RouteStubURLProtocol.reset([Self.firstPage: .failure(.notConnectedToInternet)])

            await #expect(throws: APIError.self) { try await SharedMoviesService(graph: RoutedBackend.graph()).page(1) }
        }
    }
}

@MainActor
struct MoviesViewModelTests {
    @Test func initialLoadShowsMoviesAndTotal() async throws {
        let service = MockMoviesService(pages: [1: .success(try movies(["a", "b"], total: 42, next: 2))])
        let model = MoviesViewModel(service: service)

        await model.loadIfNeeded()

        #expect(model.phase == .loaded)
        #expect(model.movies.map(\.id) == ["a", "b"])
        #expect(model.total == 42)
        #expect(model.hasMorePages)
    }

    @Test func loadMoreAppendsDedupesAndStops() async throws {
        let service = MockMoviesService(pages: [
            1: .success(try movies(["a", "b"], next: 2)),
            2: .success(try movies(["b", "c"], next: 3)),
            3: .success(try movies(["d"], next: nil)),
        ])
        let model = MoviesViewModel(service: service)
        await model.loadIfNeeded()

        await model.loadMoreIfNeeded()
        #expect(model.movies.map(\.id) == ["a", "b", "c"])

        await model.loadMoreIfNeeded()
        #expect(model.movies.map(\.id) == ["a", "b", "c", "d"])
        #expect(!model.hasMorePages)

        await model.loadMoreIfNeeded()
        #expect(service.pageCalls == [1, 2, 3])
    }

    @Test func pageOfDuplicatesKeepsLoading() async throws {
        let service = MockMoviesService(pages: [
            1: .success(try movies(["a", "b"], next: 2)),
            2: .success(try movies(["a", "b"], next: 3)),
            3: .success(try movies(["c"], next: nil)),
        ])
        let model = MoviesViewModel(service: service)
        await model.loadIfNeeded()

        await model.loadMoreIfNeeded()

        #expect(model.movies.map(\.id) == ["a", "b", "c"])
        #expect(service.pageCalls == [1, 2, 3])
    }

    @Test func failedFirstLoadShowsErrorThenRetries() async throws {
        let offline = APIError.network(code: URLError.notConnectedToInternet.rawValue)
        let service = MockMoviesService(pages: [1: .failure(offline)])
        let model = MoviesViewModel(service: service)

        await model.loadIfNeeded()
        #expect(model.phase == .failed(offline.userMessage))

        service.setPage(1, .success(try movies(["a"], next: nil)))
        await model.retry()
        #expect(model.phase == .loaded)
        #expect(model.movies.map(\.id) == ["a"])
    }

    @Test func failedLoadMoreKeepsGridAndFlagsRetry() async throws {
        let service = MockMoviesService(pages: [
            1: .success(try movies(["a"], next: 2)),
            2: .failure(APIError.api(statusCode: 500, message: nil)),
        ])
        let model = MoviesViewModel(service: service)
        await model.loadIfNeeded()

        await model.loadMoreIfNeeded()

        #expect(model.loadMoreFailed)
        #expect(model.movies.map(\.id) == ["a"])
        #expect(model.hasMorePages)
    }

    @Test func emptyCatalogueShowsEmptyState() async throws {
        let service = MockMoviesService(pages: [1: .success(try movies([], total: 0, next: nil))])
        let model = MoviesViewModel(service: service)

        await model.loadIfNeeded()

        #expect(model.phase == .empty)
    }
}

struct MoviesViewTests {
    @Test @MainActor func catalogueGridUsesAdaptiveCardWidth() {
        let columns = MoviesView.columns

        #expect(columns.count == 1)
        #expect(columns[0].spacing == 12)

        switch columns[0].size {
        case let .adaptive(minimum: minimum, maximum: maximum):
            #expect(minimum == 160)
            #expect(maximum == .infinity)
        default:
            Issue.record("MoviesView should use an adaptive grid.")
        }
    }
}
