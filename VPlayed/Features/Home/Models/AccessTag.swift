import Foundation

/// The corner tag on a content card. The shared layer decides it with the UIKit rules
/// (`SeriesCollectionViewCell`'s `configureMonetizationStatus`, then `configureCrownStatus`,
/// which can override it; decision D14) and `SharedHomeMapping` maps it.
nonisolated enum AccessTag: Hashable, Sendable {
    case comingSoon
    case price(String)
    case crown
}
