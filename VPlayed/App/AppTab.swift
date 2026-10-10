import SwiftUI

/// The app's top-level tabs, in tab-bar order. Home is the only one built so far; the others
/// show `PlaceholderDestinationView` until their screens exist.
enum AppTab: Hashable, CaseIterable, Identifiable {
    case home
    case search
    case promos
    case subscription
    case rewards

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .promos: "Promos"
        case .subscription: "Subscription"
        case .rewards: "Rewards"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .promos: "megaphone.fill"
        case .subscription: "crown.fill"
        case .rewards: "gift.fill"
        }
    }
}
