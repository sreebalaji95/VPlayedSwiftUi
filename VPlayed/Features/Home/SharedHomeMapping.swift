import Foundation
// Kotlin classes are not Sendable; they are only read on the main actor here.
@preconcurrency import Shared

/// Turns the shared layer's Home models into the structs the Home views draw. The shared mapper
/// already applied this app's image table (decision D12, `HomeImagePolicy.APPLE`), the price rule
/// (D13) and the access tag rule (D14), so this is a field-by-field copy.
nonisolated enum SharedHomeMapping {
    static func banner(_ banner: Shared.HomeBanner) -> HomeBanner {
        HomeBanner(
            id: banner.id,
            title: banner.title,
            slug: banner.slug,
            kind: ContentKind(shoType: banner.showType.map { Int($0.code) }),
            synopsis: banner.description_,
            genres: banner.genres,
            backdropURL: ImageURL.resolve(banner.imageUrl),
            titleImageURL: ImageURL.resolve(banner.titleImageUrl)
        )
    }

    /// Rows of types this app has no card for come back as `.unsupported` (the shared mapper drops
    /// them already; this keeps the switch total).
    static func section(_ section: Shared.HomeSection) -> HomeSection {
        let items = section.items
        let content: HomeSection.Content = switch section.type {
        case .video, .microSeries: .titles(items.map(contentItem))
        case .promo: .promos(items.map(contentItem))
        case .audio: .audio(items.map(audioItem))
        case .channel: .channels(items.map(channelItem))
        case .bundle: .bulkPlans(items.map(bulkPlan))
        case .live: .live(items.map(liveItem))
        default: .unsupported(type: Int(section.typeCode))
        }
        return HomeSection(id: section.id, title: section.title, type: Int(section.typeCode), isTopTen: section.isTopTen, content: content)
    }

    static func contentItem(_ item: Shared.ContentItem) -> ContentItem {
        let promo = item.details as? ItemDetailsPromo
        return ContentItem(
            id: item.id,
            title: item.title,
            slug: item.slug,
            shoType: item.showType.map { Int($0.code) },
            landscapeImageURL: ImageURL.resolve(item.landscapeImageUrl),
            portraitImageURL: ImageURL.resolve(item.portraitImageUrl),
            videoDuration: item.durationSeconds?.doubleValue,
            accessTag: accessTag(item.accessTag),
            viewCount: promo?.views.map { Int($0.int64Value) },
            likeCount: promo?.likes.map { Int($0.int64Value) },
            genre: item.genre
        )
    }

    static func audioItem(_ item: Shared.ContentItem) -> AudioItem {
        AudioItem(
            id: item.id,
            title: item.title,
            slug: item.slug,
            artistName: (item.details as? ItemDetailsAudio)?.artist,
            imageURL: ImageURL.resolve(item.imageUrl)
        )
    }

    static func channelItem(_ item: Shared.ContentItem) -> ChannelItem {
        let channel = item.details as? ItemDetailsChannel
        return ChannelItem(
            id: item.id,
            name: item.title,
            slug: item.slug,
            logoURL: ImageURL.resolve(item.imageUrl),
            followCount: channel?.followers.map { Int($0.int32Value) },
            brandHex: hex(channel?.brandColor?.int64Value),
            isFollowed: channel?.isFollowed ?? false
        )
    }

    static func bulkPlan(_ item: Shared.ContentItem) -> BulkPlan {
        let bundle = item.details as? ItemDetailsBundle
        return BulkPlan(
            id: item.id,
            name: item.title,
            slug: item.slug,
            label: bundle?.label,
            summary: bundle?.description_,
            // The UIKit card shows the full price and the listed "save up to" percentage (divergence D20).
            price: (bundle?.originalPrice ?? bundle?.price).map {
                price($0, discountedPercentage: bundle?.listedDiscountPercent?.doubleValue)
            },
            accentHex: hex(bundle?.backgroundColor?.int64Value)
        )
    }

    static func liveItem(_ item: Shared.ContentItem) -> LiveItem {
        let live = item.details as? ItemDetailsLive
        return LiveItem(
            id: item.id,
            title: item.title,
            slug: item.slug,
            channelName: live?.channelName,
            isLive: live?.status == .live,
            startsAt: live?.startsAtMillis.map { Date(timeIntervalSince1970: Double($0.int64Value) / 1000) },
            imageURL: ImageURL.resolve(item.imageUrl)
        )
    }

    static func accessTag(_ tag: (any Shared.AccessTag)?) -> AccessTag? {
        switch tag {
        case is AccessTagComingSoon: .comingSoon
        case is AccessTagCrown: .crown
        case let paid as AccessTagPaid: price(paid.price).formatted.map(AccessTag.price)
        default: nil
        }
    }

    /// Without a `currency_sign` the shared price carries the currency code; this app shows its
    /// own symbol for the code instead (`Price.formatted`).
    static func price(_ price: Shared.Price, discountedPercentage: Double? = nil) -> Price {
        Price(
            currency: price.currency.isEmpty ? nil : price.currency,
            currencySign: price.hasSign ? price.currencySign : nil,
            currencyType: price.currencyType.map { Int($0.int32Value) },
            amount: price.amount,
            discountedPercentage: discountedPercentage
        )
    }

    /// `#RRGGBB` for an opaque ARGB colour (`Color(hexString:)` reads six digits only).
    static func hex(_ argb: Int64?) -> String? {
        guard let argb, argb >> 24 & 0xFF == 0xFF else { return nil }
        return String(format: "#%06X", argb & 0xFFFFFF)
    }
}
