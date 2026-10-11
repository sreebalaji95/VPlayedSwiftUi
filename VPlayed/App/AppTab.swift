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
        case .home: String(localized: "Home", bundle: .localized)
        case .promos: String(localized: "Promos", bundle: .localized)
        case .subscription: String(localized: "Subscription", bundle: .localized)
        case .search: String(localized: "Search", bundle: .localized)
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
