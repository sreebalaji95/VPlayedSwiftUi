import Foundation
import Testing
@testable import VPlayed

struct ImageURLTests {
    let cdn = URL(string: "https://cdn.example.com/")!

    @Test func relativeKeysJoinTheCDN() {
        let url = ImageURL.resolve("gudsho-upload/13-06-2026/a b.jpg", imageBaseURL: cdn)
        #expect(url?.absoluteString == "https://cdn.example.com/gudsho-upload/13-06-2026/a%20b.jpg")
    }

    @Test func absoluteURLsPassThrough() {
        let url = ImageURL.resolve("https://gsvp-dev.s3.ap-south-1.amazonaws.com/static/images/blue.png", imageBaseURL: cdn)
        #expect(url?.host() == "gsvp-dev.s3.ap-south-1.amazonaws.com")
    }

    @Test(arguments: [nil, "", "   "])
    func missingPathsResolveToNil(_ path: String?) {
        #expect(ImageURL.resolve(path, imageBaseURL: cdn) == nil)
    }

    @Test func imageSetPrefersVariantOrderThenTheOriginalOverWebP() throws {
        let json = #"""
        {"webp":{"tp":"p.webp","tm":"m.webp"},"default":{"tv":"v.jpg","tp":"p.jpg"},"avif":null}
        """#
        let set = try JSONDecoder().decode(ImageSet.self, from: Data(json.utf8))
        #expect(set.path(preferring: [.tv, .tp]) == "v.jpg")
        #expect(set.path(preferring: [.tp]) == "p.jpg")
        #expect(set.path(preferring: [.tm]) == "m.webp")
        #expect(set.path(preferring: [.tc]) == nil)
    }

    @Test func malformedImageSetDecodesEmpty() throws {
        let set = try JSONDecoder().decode(ImageSet.self, from: Data(#""oops""#.utf8))
        #expect(set.formats.isEmpty)
    }
}

/// Ported from `SeriesCollectionViewCell.configureMonetizationStatus` + `configureCrownStatus`.
struct AccessTagTests {
    let inr: [String: Any] = ["currency": "INR", "currency_type": 1, "amount": 33]
    let usd: [String: Any] = ["currency": "USD", "currency_type": 2, "amount": 12.5]

    @Test(arguments: [4, 6, 7])
    func upcomingMonetizationShowsComingSoon(_ monetization: Int) throws {
        let item = try makeItem(monetization: monetization, prices: [inr])
        #expect(AccessTag.resolve(for: item) == .comingSoon)
    }

    @Test func freeTitlesHaveNoTag() throws {
        #expect(AccessTag.resolve(for: try makeItem(monetization: 5, prices: [inr])) == nil)
        #expect(AccessTag.resolve(for: try makeItem(monetization: 2, prices: [inr])) == nil)
    }

    @Test func payPerViewShowsPreferredCurrencyPrice() throws {
        let item = try makeItem(monetization: 1, prices: [usd, inr])
        #expect(AccessTag.resolve(for: item) == .price("₹33"))
    }

    @Test func subscriptionTitleShowsCrownUntilSubscribed() throws {
        #expect(AccessTag.resolve(for: try makeItem(monetization: 1, prices: [inr], isSubscription: true, isUserSubscribed: false)) == .crown)
        #expect(AccessTag.resolve(for: try makeItem(monetization: 8, isSubscription: true, isUserSubscribed: false)) == .crown)
        #expect(AccessTag.resolve(for: try makeItem(monetization: 8, isSubscription: true, isUserSubscribed: true)) == nil)
    }

    @Test func comingSoonSubscriptionTitleShowsCrown() throws {
        let item = try makeItem(monetization: 7, isSubscription: true, isUserSubscribed: false)
        #expect(AccessTag.resolve(for: item) == .crown)
    }

    @Test func scheduledPayPerViewHidesPrice() throws {
        #expect(AccessTag.resolve(for: try makeItem(monetization: 1, prices: [inr], scheduled: true)) == nil)
    }

    @Test func priceFormatting() {
        #expect(Price(currency: "INR", currencyType: 1, amount: 33).formatted == "₹33")
        #expect(Price(currency: "USD", currencyType: 2, amount: 12.5).formatted == "$12.50")
        #expect(Price(currency: "INR", currencySign: "Rs.", currencyType: 1, amount: 5).formatted == "Rs.5")
        #expect(Price(currency: "INR", currencyType: 1, amount: nil).formatted == nil)
    }
}
