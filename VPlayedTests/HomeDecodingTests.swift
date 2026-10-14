import Foundation
import Testing
@testable import VPlayed

/// Decoding against responses captured from `api-devgs.vplayed.com` (trimmed to 2 items per rail).
struct HomeDecodingTests {
    @Test func firstPageDecodesRailsInServerOrder() throws {
        let page = try Fixture.payload("home-page-1", as: HomeFeedPage.self)

        #expect(page.sections.map(\.title) == ["Bulk purchase", "Videos / Series", "Popular Channels"])
        #expect(page.sections.map(\.type) == [5, 1, 4])
        #expect(page.sections.map(\.layout) == [.bulkPlans, .landscape, .channels])
        #expect(page.nextPage == 2)
        #expect(page.sections.allSatisfy { $0.isDisplayable })
    }

    @Test func videoItemsMapCardFields() throws {
        let page = try Fixture.payload("home-page-1", as: HomeFeedPage.self)
        guard case .titles(let items) = page.sections[1].content, let item = items.first else {
            Issue.record("Videos / Series should decode as titles")
            return
        }
        #expect(item.title == "Blood Father1")
        #expect(item.slug == "blood-father")
        #expect(item.shoType == 1)
        #expect(item.videoDuration == 267.72)
        #expect(item.landscapeImageURL?.host() == "gsvp-dev.s3.ap-south-1.amazonaws.com")
        // The sharpest 16:9 variant, as the original rather than WebP.
        #expect(item.landscapeImageURL?.lastPathComponent.contains("-tc-") == true)
        #expect(item.landscapeImageURL?.pathExtension != "webp")
        #expect(item.portraitImageURL?.path().contains("thumbnail-images") == true)
    }

    @Test func channelsAndBulkPlansDecode() throws {
        let page = try Fixture.payload("home-page-1", as: HomeFeedPage.self)
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

    @Test func audioLiveAndTopTenMicroSeries() throws {
        let page = try Fixture.payload("home-page-3", as: HomeFeedPage.self)
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

    @Test func topTenVideosUseRankedLandscapeAndPromosUsePromoCards() throws {
        let page = try Fixture.payload("home-page-4", as: HomeFeedPage.self)
        #expect(page.sections.map(\.layout) == [.rankedLandscape, .promos, .live])

        guard case .promos(let promos) = page.sections[1].content, let promo = promos.first else {
            Issue.record("Latest Promos should decode as promos")
            return
        }
        #expect(page.sections[1].kind(for: promo) == .promo)
        #expect(promo.formattedDuration != nil)
    }

    @Test func lastPageHasNoNextPage() throws {
        let page = try Fixture.payload("home-page-6", as: HomeFeedPage.self)
        #expect(page.nextPage == nil)
        #expect(page.sections.count == 3)
    }

    @Test func bannersDecodeHeroFields() throws {
        let list = try Fixture.payload("home-banners", as: HomeBannerList.self)
        #expect(list.banners.count == 2)

        let banner = try #require(list.banners.first)
        #expect(banner.title == "Captain America: Brave New World")
        #expect(banner.kind == .series)
        #expect(banner.slug == "captain-america:-brave-new-world")
        #expect(banner.synopsis?.hasPrefix("Following the events of Avengers") == true)
        #expect(banner.genres == ["Action"])
        #expect(banner.backdropURL?.path().contains("video-banner-images") == true)
        #expect(banner.titleImageURL?.path().contains("title-images") == true)
    }

    @Test func unknownRailTypesAndEmptyRailsAreNotDisplayable() throws {
        let unknown = try HomeSection.decode(#"{"_id":"x","title":"Reward","type":12,"data":[{"enabled":true}]}"#)
        #expect(unknown.content == .unsupported(type: 12))
        #expect(unknown.layout == nil)
        #expect(!unknown.isDisplayable)

        let empty = try HomeSection.decode(#"{"_id":"y","title":"Continue","type":1,"data":[]}"#)
        #expect(!empty.isDisplayable)

        let missingData = try HomeSection.decode(#"{"_id":"z","title":"No data","type":1}"#)
        #expect(!missingData.isDisplayable)
    }

    @Test func malformedItemsAreDroppedNotFatal() throws {
        let section = try HomeSection.decode(#"""
        {"_id":"s","title":"Mixed","type":1,"data":[
          {"title":"no id"},
          {"_id":"ok","title":"Kept","sho_type":"6","video_duration":"206.64"},
          42,
          null
        ]}
        """#)
        guard case .titles(let items) = section.content else {
            Issue.record("Expected titles")
            return
        }
        #expect(items.map(\.id) == ["ok"])
        #expect(items.first?.shoType == 6)
        #expect(items.first?.videoDuration == 206.64)
        #expect(section.layout == .portrait)
    }

    @Test func localizedTitlesAcceptStringOrTranslations() throws {
        let plain = try HomeSection.decode(#"{"_id":"a","title":"Plain","type":5,"data":[]}"#)
        let translated = try HomeSection.decode(#"{"_id":"b","title":{"en":"Bulk purchase","ta":"x"},"type":5,"data":[]}"#)
        #expect(plain.title == "Plain")
        #expect(translated.title == "Bulk purchase")
    }

    @Test func pageWithoutNextOrWithZeroNextEnds() throws {
        let zero = try JSONDecoder().decode(HomeFeedPage.self, from: Data(#"{"data":[],"next":0}"#.utf8))
        let missing = try JSONDecoder().decode(HomeFeedPage.self, from: Data(#"{"data":[]}"#.utf8))
        #expect(zero.nextPage == nil)
        #expect(missing.nextPage == nil)
    }
}
