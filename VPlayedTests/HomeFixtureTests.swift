import Foundation
@preconcurrency import Shared
import Testing
@testable import VPlayed

extension RoutedBackendTests {
    /// Responses captured from `api-devgs.vplayed.com` (trimmed to 2 items per rail, people
    /// pseudonymised) through the shared layer and `SharedHomeMapping`, as the app reads them.
    @MainActor
    @Suite
    struct HomeFixtureTests {
        private let repository = RoutedBackend.graph().homeRepository

        /// The rails and next page the Home views get for a `home` answer.
        private func page(_ answer: RouteStubURLProtocol.Answer) async throws -> (sections: [VPlayed.HomeSection], nextPage: Int?) {
            RouteStubURLProtocol.reset([RoutedBackend.home(1): answer])
            let result = try await repository.getSections(page: 1)
            let page = try #require((result as? DataResultSuccess<HomeSectionsPage>)?.data)
            return (page.sections.map(SharedHomeMapping.section), page.nextPage.map { Int(truncating: $0) })
        }

        private func page(fixture: String) async throws -> (sections: [VPlayed.HomeSection], nextPage: Int?) {
            try await page(RoutedBackend.fixture(fixture))
        }

        /// A page holding the given rails, for edge cases.
        private func page(rails: [String], next: String = "null") async throws -> (sections: [VPlayed.HomeSection], nextPage: Int?) {
            try await page(.json(status: 200, body: #"{"statusCode":200,"response":{"data":[\#(rails.joined(separator: ","))],"next":\#(next)}}"#))
        }

        @Test func firstPageKeepsRailsInServerOrder() async throws {
            let page = try await page(fixture: "home-page-1")

            #expect(page.sections.map(\.title) == ["Bulk purchase", "Videos / Series", "Popular Channels"])
            #expect(page.sections.map(\.type) == [5, 1, 4])
            #expect(page.sections.map(\.layout) == [.bulkPlans, .landscape, .channels])
            #expect(page.nextPage == 2)
            #expect(page.sections.allSatisfy { $0.isDisplayable })
        }

        @Test func videoItemsMapCardFields() async throws {
            let page = try await page(fixture: "home-page-1")
            guard case .titles(let items) = page.sections[1].content, let item = items.first else {
                Issue.record("Videos / Series should map to titles")
                return
            }
            #expect(item.title == "Blood Father1")
            #expect(item.slug == "blood-father")
            #expect(item.shoType == 1)
            #expect(item.videoDuration == 267.72)
            #expect(item.landscapeImageURL?.host() == "gsvp-dev.s3.ap-south-1.amazonaws.com")
            // The sharpest 16:9 variant, as the original rather than WebP (D12, Apple table).
            #expect(item.landscapeImageURL?.lastPathComponent.contains("-tc-") == true)
            #expect(item.landscapeImageURL?.pathExtension != "webp")
            #expect(item.portraitImageURL?.path().contains("thumbnail-images") == true)
        }

        @Test func channelsAndBulkPlansMap() async throws {
            let page = try await page(fixture: "home-page-1")
            guard case .bulkPlans(let plans) = page.sections[0].content,
                  case .channels(let channels) = page.sections[2].content
            else {
                Issue.record("Unexpected section content")
                return
            }
            #expect(plans.first?.name == "Channel A")
            #expect(plans.first?.label == "Special ony for you")
            #expect(plans.first?.price?.formatted == "₹1")
            #expect(channels.first?.name == "Channel C")
            #expect(channels.first?.logoURL?.absoluteString == "https://gsvp-dev.s3.ap-south-1.amazonaws.com/images/1779980945139-blob.png")
        }

        @Test func audioLiveAndTopTenMicroSeries() async throws {
            let page = try await page(fixture: "home-page-3")
            #expect(page.sections.map(\.layout) == [.audio, .live, .rankedPortrait])

            guard case .audio(let tracks) = page.sections[0].content,
                  case .live(let streams) = page.sections[1].content,
                  case .titles(let micro) = page.sections[2].content
            else {
                Issue.record("Unexpected section content")
                return
            }
            #expect(tracks.first?.artistName == "Artist A")
            #expect(tracks.first?.imageURL != nil)
            #expect(streams.first?.channelName == "Channel C")
            #expect(streams.first?.isLive == false)
            #expect(micro.allSatisfy { $0.isMicroSeries })
            // Micro-series `tc` is tiny; `tp` is their largest 3:4 variant.
            #expect(micro.first?.portraitImageURL?.lastPathComponent.contains("-tp-") == true)
            #expect(page.sections[2].showsViewAll == false)
        }

        /// Decision D10: live items read AndroidJP's `schedule_at` too, so a scheduled stream shows its start time.
        @Test func liveItemsReadTheScheduleKey() async throws {
            let page = try await page(fixture: "home-page-3")
            guard case .live(let streams) = page.sections.first(where: { $0.layout == .live })?.content else {
                Issue.record("Expected a live rail")
                return
            }
            let scheduled = try #require(streams.first { $0.title == "Future Plan" })
            #expect(scheduled.startsAt == Date(timeIntervalSince1970: 1_791_570_600))
        }

        @Test func topTenVideosUseRankedLandscapeAndPromosUsePromoCards() async throws {
            let page = try await page(fixture: "home-page-4")
            #expect(page.sections.map(\.layout) == [.rankedLandscape, .promos, .live])

            guard case .promos(let promos) = page.sections[1].content, let promo = promos.first else {
                Issue.record("Latest Promos should map to promos")
                return
            }
            #expect(page.sections[1].kind(for: promo) == .promo)
            #expect(promo.formattedDuration != nil)
        }

        @Test func lastPageHasNoNextPage() async throws {
            let page = try await page(fixture: "home-page-6")
            #expect(page.nextPage == nil)
            #expect(page.sections.count == 3)
        }

        @Test func bannersMapHeroFields() async throws {
            RouteStubURLProtocol.reset([RoutedBackend.banners: try RoutedBackend.fixture("home-banners")])
            let result = try await repository.getBanners()
            let banners = try #require((result as? DataResultSuccess<NSArray>)?.data as? [Shared.HomeBanner]).map(SharedHomeMapping.banner)
            #expect(banners.count == 2)

            let banner = try #require(banners.first)
            #expect(banner.title == "Captain America: Brave New World")
            #expect(banner.kind == .series)
            #expect(banner.slug == "captain-america:-brave-new-world")
            #expect(banner.synopsis?.hasPrefix("Following the events of Avengers") == true)
            #expect(banner.genres == ["Action"])
            #expect(banner.backdropURL?.path().contains("video-banner-images") == true)
            #expect(banner.titleImageURL?.path().contains("title-images") == true)
        }

        /// Decision D7: rails of unknown types and rails without items are dropped.
        @Test func unknownRailTypesAndEmptyRailsAreDropped() async throws {
            let page = try await page(rails: [
                #"{"_id":"x","title":"Reward","type":12,"data":[{"enabled":true}]}"#,
                #"{"_id":"y","title":"Continue","type":1,"data":[]}"#,
                #"{"_id":"z","title":"No data","type":1}"#,
            ])

            #expect(page.sections.isEmpty)
        }

        @Test func malformedItemsAreDroppedNotFatal() async throws {
            let page = try await page(rails: [#"""
            {"_id":"s","title":"Mixed","type":1,"data":[
              {"title":"no id"},
              {"_id":"ok","title":"Kept","sho_type":"6","video_duration":"206.64"},
              42,
              null
            ]}
            """#])
            let section = try #require(page.sections.first)
            guard case .titles(let items) = section.content else {
                Issue.record("Expected titles")
                return
            }
            #expect(items.map(\.id) == ["ok"])
            #expect(items.first?.shoType == 6)
            #expect(items.first?.videoDuration == 206.64)
            #expect(section.layout == .portrait)
        }

        @Test func localizedTitlesAcceptStringOrTranslations() async throws {
            let page = try await page(rails: [
                #"{"_id":"a","title":"Plain","type":1,"data":[{"_id":"i1","title":"One"}]}"#,
                #"{"_id":"b","title":{"en":"Videos","ta":"x"},"type":1,"data":[{"_id":"i2","title":"Two"}]}"#,
            ])
            #expect(page.sections.map(\.title) == ["Plain", "Videos"])
        }

        @Test func pageWithoutNextOrWithZeroNextEnds() async throws {
            #expect(try await page(rails: [], next: "0").nextPage == nil)
            #expect(try await page(rails: []).nextPage == nil)
        }
    }
}
