import Foundation

/// Data source for the Home screen.
nonisolated protocol HomeServicing: Sendable {
    func banners() async throws -> [HomeBanner]
    func homePage(_ page: Int) async throws -> HomeFeedPage
}

nonisolated struct HomeService: HomeServicing {
    var client: APIClient = .shared

    func banners() async throws -> [HomeBanner] {
        try await client.get(.homeBanners, as: HomeBannerList.self).banners
    }

    func homePage(_ page: Int) async throws -> HomeFeedPage {
        try await client.get(.home(page: page), as: HomeFeedPage.self)
    }
}
