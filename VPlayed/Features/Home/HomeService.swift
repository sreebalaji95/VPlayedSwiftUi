import Foundation

/// Data source for the Home screen.
nonisolated protocol HomeServicing: Sendable {
    func banners() async throws -> [HomeBanner]
    func homePage(_ page: Int) async throws -> HomeFeedPage
    func setFollowing(_ follow: Bool, channelSlug: String) async throws
}

nonisolated struct HomeService: HomeServicing {
    var client: APIClient = .shared

    private struct FollowBody: Encodable, Sendable {
        let studio: String
        let follow: String
    }

    func banners() async throws -> [HomeBanner] {
        try await client.get(.homeBanners, as: HomeBannerList.self).banners
    }

    func homePage(_ page: Int) async throws -> HomeFeedPage {
        try await client.get(.home(page: page), as: HomeFeedPage.self)
    }

    /// UIKit sends the new state as a string (`StudiosViewModel.followStudioAPI`).
    func setFollowing(_ follow: Bool, channelSlug: String) async throws {
        let body = FollowBody(studio: channelSlug, follow: follow ? "1" : "0")
        _ = try await client.post(.followChannel, body: body, as: IgnoredPayload.self, accepting: [200, 201])
    }
}
