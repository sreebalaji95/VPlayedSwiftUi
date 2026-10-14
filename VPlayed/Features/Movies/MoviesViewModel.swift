import Foundation
import Observation

/// Drives the Movies grid: the catalogue total plus paged, de-duplicated movies.
@Observable
final class MoviesViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var movies: [ContentItem] = []
    private(set) var total: Int?
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    /// A non-blocking error to surface as a toast (a refresh failed but the grid is still shown).
    var notice: String?

    var hasMorePages: Bool { nextPage != nil }

    private let service: any MoviesServicing
    private var nextPage: Int?
    /// Bumped on every full reload so responses from superseded loads are discarded.
    private var generation = 0

    init(service: any MoviesServicing = SharedMoviesService()) {
        self.service = service
    }

    func loadIfNeeded() async {
        guard phase == .idle else { return }
        phase = .loading
        await reload(isInitial: true)
    }

    func retry() async {
        phase = .loading
        await reload(isInitial: true)
    }

    /// Pull-to-refresh: reloads the first page, keeping the current grid on failure.
    func refresh() async {
        await reload(isInitial: phase != .loaded)
    }

    /// Fetches the next page when the end of the grid becomes visible.
    func loadMoreIfNeeded() async {
        guard phase == .loaded, !isLoadingMore, let page = nextPage else { return }
        isLoadingMore = true
        loadMoreFailed = false
        let token = generation
        defer { if token == generation { isLoadingMore = false } }

        var pageToLoad: Int? = page
        var emptyPages = 0
        while let current = pageToLoad {
            do {
                let result = try await service.page(current)
                guard token == generation else { return }
                let added = append(result.items)
                total = result.total ?? total
                // Guard against a server that repeats or rewinds the page number.
                nextPage = result.nextPage.flatMap { $0 > current ? $0 : nil }
                // A page of only duplicates leaves the footer's trigger unchanged, so keep going.
                emptyPages = added == 0 ? emptyPages + 1 : 0
                pageToLoad = added == 0 && emptyPages < maxEmptyPagesInARow ? nextPage : nil
            } catch {
                guard token == generation else { return }
                if !(error is CancellationError) { loadMoreFailed = true }
                return
            }
        }
    }

    /// Caps how many consecutive pages are fetched when a page adds nothing new.
    private let maxEmptyPagesInARow = 5

    private func reload(isInitial: Bool) async {
        generation += 1
        let token = generation
        isLoadingMore = false
        loadMoreFailed = false

        do {
            let result = try await service.page(1)
            guard token == generation else { return }
            movies = []
            _ = append(result.items)
            total = result.total
            nextPage = result.nextPage
            phase = movies.isEmpty && nextPage == nil ? .empty : .loaded
        } catch is CancellationError {
            // The view went away mid-load; start over next time it appears.
            if isInitial, token == generation { phase = .idle }
        } catch {
            guard token == generation else { return }
            let message = (error as? APIError)?.userMessage ?? APIError.network(code: 0).userMessage
            if isInitial {
                phase = .failed(message)
            } else {
                notice = message
            }
        }
    }

    /// Appends movies not already shown (pages can overlap when the catalogue changes); returns
    /// how many were added.
    private func append(_ items: [ContentItem]) -> Int {
        var seen = Set(movies.map(\.id))
        let fresh = items.filter { seen.insert($0.id).inserted }
        movies.append(contentsOf: fresh)
        return fresh.count
    }
}
