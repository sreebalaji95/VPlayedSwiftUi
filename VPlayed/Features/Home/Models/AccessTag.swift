import Foundation

/// The corner tag on a content card. A port of `SeriesCollectionViewCell`'s
/// `configureMonetizationStatus` followed by `configureCrownStatus` (which can override it).
nonisolated enum AccessTag: Hashable, Sendable {
    case comingSoon
    case price(String)
    case crown

    /// The tag decided when the item was read (by `resolve(monetization:…)` below, or by the shared
    /// layer's port of it, decision D14).
    static func resolve(for item: ContentItem) -> AccessTag? {
        item.accessTag
    }

    static func resolve(
        monetization: Int?,
        price: Price?,
        isSubscription: Bool?,
        isUserSubscribed: Bool?,
        isScheduled: Bool?
    ) -> AccessTag? {
        let subscribed = isUserSubscribed ?? false
        let priceTag = price?.formatted.map(AccessTag.price)

        // Monetization status: 4/6/7 upcoming, 5 free, otherwise the price unless subscribed.
        var tag: AccessTag?
        switch monetization {
        case 4, 6, 7: tag = .comingSoon
        case 5: tag = nil
        default: tag = subscribed ? nil : priceTag
        }

        // Crown pass.
        switch monetization {
        case 6, 7, 8:
            if let isSubscription, let isUserSubscribed {
                if isSubscription && !isUserSubscribed {
                    tag = .crown
                } else if isUserSubscribed {
                    tag = nil
                }
            }
        case 1:
            if isSubscription == true && !subscribed {
                tag = .crown
            } else {
                tag = isScheduled == true ? nil : priceTag
            }
        case 2, 5:
            tag = nil
        default:
            if isSubscription == true && !subscribed {
                tag = .crown
            }
        }
        return tag
    }
}
