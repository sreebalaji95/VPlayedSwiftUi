import Foundation
import Testing
@testable import VPlayed

/// Scripted `HomeServicing` for ViewModel tests. Development-only; never used by the app.
final class MockHomeService: HomeServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var bannerResult: Result<[HomeBanner], any Error>
    private var pages: [Int: Result<HomeFeedPage, any Error>]
    private var calls: [Int] = []
    private let pageDelay: Duration?

    init(
        banners: Result<[HomeBanner], any Error> = .success([]),
        pages: [Int: Result<HomeFeedPage, any Error>],
        pageDelay: Duration? = nil
    ) {
        bannerResult = banners
        self.pages = pages
        self.pageDelay = pageDelay
    }

    var pageCalls: [Int] { lock.withLock { calls } }

    func setPage(_ page: Int, _ result: Result<HomeFeedPage, any Error>) {
        lock.withLock { pages[page] = result }
    }

    func setBanners(_ result: Result<[HomeBanner], any Error>) {
        lock.withLock { bannerResult = result }
    }

    func banners() async throws -> [HomeBanner] {
        try lock.withLock { bannerResult }.get()
    }

    func homePage(_ page: Int) async throws -> HomeFeedPage {
        lock.withLock { calls.append(page) }
        if let pageDelay { try await Task.sleep(for: pageDelay) }
        guard let result = lock.withLock({ pages[page] }) else { throw APIError.http(statusCode: 404) }
        return try result.get()
    }
}

private func rail(_ id: String, items: Int = 1, type: Int = 1) throws -> HomeSection {
    let data = (0..<items).map { #"{"_id":"\#(id)-\#($0)","title":"Item \#($0)","sho_type":1}"# }.joined(separator: ",")
    return try HomeSection.decode(#"{"_id":"\#(id)","title":"Rail \#(id)","type":\#(type),"data":[\#(data)]}"#)
}

private func page(_ sections: [HomeSection], next: Int?) -> HomeFeedPage {
    HomeFeedPage(sections: sections, nextPage: next)
}

@MainActor
struct HomeViewModelTests {
    @Test func initialLoadShowsBannersAndRails() async throws {
        let banners = try Fixture.payload("home-banners", as: HomeBannerList.self).banners
        let service = MockHomeService(
            banners: .success(banners),
            pages: [1: .success(page([try rail("a"), try rail("b")], next: 2))]
        )
        let model = HomeViewModel(service: service)
        #expect(model.phase == .idle)

        await model.loadIfNeeded()

        #expect(model.phase == .loaded)
        #expect(model.banners.count == 2)
        #expect(model.sections.map(\.id) == ["a", "b"])
        #expect(model.hasMorePages)
    }

    @Test func loadIfNeededRunsOnlyOnce() async throws {
        let service = MockHomeService(pages: [1: .success(page([try rail("a")], next: nil))])
        let model = HomeViewModel(service: service)

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(service.pageCalls == [1])
    }

    @Test func hidesUnsupportedAndEmptyRails() async throws {
        let service = MockHomeService(pages: [1: .success(page([
            try rail("shown"),
            try rail("empty", items: 0),
            try HomeSection.decode(#"{"_id":"reward","title":"Reward","type":12,"data":[{"enabled":true}]}"#),
        ], next: nil))])
        let model = HomeViewModel(service: service)

        await model.loadIfNeeded()

        #expect(model.sections.map(\.id) == ["shown"])
    }

    @Test func bannerFailureIsNotFatal() async throws {
        let service = MockHomeService(
            banners: .failure(APIError.http(statusCode: 500)),
            pages: [1: .success(page([try rail("a")], next: nil))]
        )
        let model = HomeViewModel(service: service)

        await model.loadIfNeeded()

        #expect(model.phase == .loaded)
        #expect(model.banners.isEmpty)
        #expect(model.sections.count == 1)
    }

    @Test func railFailureShowsErrorThenRetryRecovers() async throws {
        let service = MockHomeService(pages: [1: .failure(APIError.network(code: URLError.notConnectedToInternet.rawValue))])
        let model = HomeViewModel(service: service)

        await model.loadIfNeeded()
        #expect(model.phase == .failed(APIError.network(code: URLError.notConnectedToInternet.rawValue).userMessage))

        service.setPage(1, .success(page([try rail("a")], next: nil)))
        await model.retry()
        #expect(model.phase == .loaded)
        #expect(model.sections.count == 1)
    }

    @Test func emptyFeedShowsEmptyState() async throws {
        let model = HomeViewModel(service: MockHomeService(pages: [1: .success(page([], next: nil))]))
        await model.loadIfNeeded()
        #expect(model.phase == .empty)
    }

    @Test func refreshFailureKeepsContentAndShowsNotice() async throws {
        let service = MockHomeService(pages: [1: .success(page([try rail("a")], next: nil))])
        let model = HomeViewModel(service: service)
        await model.loadIfNeeded()

        service.setPage(1, .failure(APIError.http(statusCode: 500)))
        await model.refresh()

        #expect(model.phase == .loaded)
        #expect(model.sections.map(\.id) == ["a"])
        #expect(model.notice != nil)
    }

    @Test func refreshReplacesContentAndResetsPaging() async throws {
        let service = MockHomeService(pages: [
            1: .success(page([try rail("a")], next: 2)),
            2: .success(page([try rail("b")], next: nil)),
        ])
        let model = HomeViewModel(service: service)
        await model.loadIfNeeded()
        await model.loadMoreIfNeeded()
        #expect(model.sections.map(\.id) == ["a", "b"])

        service.setPage(1, .success(page([try rail("fresh")], next: 2)))
        await model.refresh()

        #expect(model.sections.map(\.id) == ["fresh"])
        #expect(model.hasMorePages)
    }

    @Test func loadMoreAppendsDedupesAndStops() async throws {
        let service = MockHomeService(pages: [
            1: .success(page([try rail("a")], next: 2)),
            2: .success(page([try rail("a"), try rail("b")], next: 3)),
            3: .success(page([try rail("c")], next: nil)),
        ])
        let model = HomeViewModel(service: service)
        await model.loadIfNeeded()

        await model.loadMoreIfNeeded()
        #expect(model.sections.map(\.id) == ["a", "b"])
        await model.loadMoreIfNeeded()
        #expect(model.sections.map(\.id) == ["a", "b", "c"])
        #expect(!model.hasMorePages)

        await model.loadMoreIfNeeded()
        #expect(service.pageCalls == [1, 2, 3])
    }

    @Test func concurrentLoadMoreRequestsThePageOnce() async throws {
        let service = MockHomeService(
            pages: [
                1: .success(page([try rail("a")], next: 2)),
                2: .success(page([try rail("b")], next: nil)),
            ],
            pageDelay: .milliseconds(50)
        )
        let model = HomeViewModel(service: service)
        await model.loadIfNeeded()

        async let first: Void = model.loadMoreIfNeeded()
        async let second: Void = model.loadMoreIfNeeded()
        _ = await (first, second)

        #expect(service.pageCalls == [1, 2])
        #expect(model.sections.map(\.id) == ["a", "b"])
    }

    @Test func pagesWithNothingDisplayableAreSkipped() async throws {
        let service = MockHomeService(pages: [
            1: .success(page([try rail("a")], next: 2)),
            2: .success(page([try rail("empty", items: 0)], next: 3)),
            3: .success(page([try rail("c")], next: nil)),
        ])
        let model = HomeViewModel(service: service)
        await model.loadIfNeeded()

        await model.loadMoreIfNeeded()

        #expect(model.sections.map(\.id) == ["a", "c"])
        #expect(service.pageCalls == [1, 2, 3])
    }

    @Test func loadMoreFailureIsRetryable() async throws {
        let service = MockHomeService(pages: [1: .success(page([try rail("a")], next: 2))])
        let model = HomeViewModel(service: service)
        await model.loadIfNeeded()

        await model.loadMoreIfNeeded()
        #expect(model.loadMoreFailed)
        #expect(model.hasMorePages)

        service.setPage(2, .success(page([try rail("b")], next: nil)))
        await model.loadMoreIfNeeded()
        #expect(!model.loadMoreFailed)
        #expect(model.sections.map(\.id) == ["a", "b"])
    }

    @Test func serverRepeatingAPageNumberDoesNotLoop() async throws {
        let service = MockHomeService(pages: [
            1: .success(page([try rail("a")], next: 2)),
            2: .success(page([try rail("b")], next: 2)),
        ])
        let model = HomeViewModel(service: service)
        await model.loadIfNeeded()

        await model.loadMoreIfNeeded()

        #expect(!model.hasMorePages)
        #expect(service.pageCalls == [1, 2])
    }
}
