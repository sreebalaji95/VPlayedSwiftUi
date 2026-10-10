import SwiftUI

/// Every destination Home can open. Only Home exists so far; each route currently resolves
/// to `PlaceholderDestinationView` until the real screen is built.
enum AppRoute: Hashable {
    case content(slug: String?, title: String, kind: ContentKind)
    case channel(slug: String?, name: String)
    case bulkPlan(slug: String?, name: String)
    case viewAll(sectionID: String, title: String)
    case search
    case voiceSearch
    case notifications
    case menu
    /// Actions that need a signed-in user (watchlist, reminders) — there is no sign-in yet.
    case signInRequired(action: String)
}

/// Lets any Home subview request navigation without threading closures through every card.
struct RouteAction {
    private let handler: (AppRoute) -> Void

    init(_ handler: @escaping (AppRoute) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ route: AppRoute) {
        handler(route)
    }
}

extension EnvironmentValues {
    @Entry var openRoute = RouteAction { _ in }
}
