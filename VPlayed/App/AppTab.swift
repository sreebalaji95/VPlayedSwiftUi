import SwiftUI

/// The app's top-level tabs, in tab-bar order. Home is the only one built so far; the others
/// show `PlaceholderDestinationView` until their screens exist.
enum AppTab: Hashable, CaseIterable, Identifiable {
    case home
    case promos
    case subscription
    case search

    var id: Self { self }

    var title: String {
        switch self {
        case .home: L10n.string(.navHome)
        case .promos: L10n.string(.navPromos)
        case .subscription: L10n.string(.navSubscription)
        case .search: L10n.string(.navSearch)
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .promos: "megaphone.fill"
        case .subscription: "crown.fill"
        case .search: "magnifyingglass"
        }
    }
}
