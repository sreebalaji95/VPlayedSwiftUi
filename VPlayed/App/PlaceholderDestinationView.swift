import SwiftUI

/// Stand-in for screens that are not built yet. Shows exactly what was requested so the
/// navigation wiring can be verified and the real screen dropped in later.
struct PlaceholderDestinationView: View {
    private let symbol: String
    private let title: String
    private let navigationTitle: String
    private let details: [String]

    init(route: AppRoute) {
        symbol = Self.symbol(for: route)
        title = Self.title(for: route)
        navigationTitle = Self.navigationTitle(for: route)
        details = Self.details(for: route)
    }

    init(tab: AppTab) {
        symbol = tab.symbol
        title = tab.title
        navigationTitle = tab.title
        details = []
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 76, height: 76)
                .background(Theme.Palette.raised, in: .rect(cornerRadius: Theme.Radius.popover))

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Text("This screen isn't built yet.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background)
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private static func navigationTitle(for route: AppRoute) -> String {
        switch route {
        case .content: "Details"
        case .channel: "Channel"
        case .bulkPlan: "Bulk purchase"
        case .viewAll: "View all"
        case .search: "Search"
        case .voiceSearch: "Voice search"
        case .notifications: "Notifications"
        case .menu: "Menu"
        case .signInRequired: "Sign in"
        }
    }

    private static func title(for route: AppRoute) -> String {
        switch route {
        case .content(_, let title, _): title
        case .channel(_, let name): name
        case .bulkPlan(_, let name): name
        case .viewAll(_, let title): title
        case .signInRequired(let action): "Sign in to \(action.lowercased())"
        default: navigationTitle(for: route)
        }
    }

    private static func details(for route: AppRoute) -> [String] {
        switch route {
        case .content(let slug, _, let kind):
            ["\(kind.displayName) detail", slug.map { "slug: \($0)" }].compactMap { $0 }
        case .channel(let slug, _), .bulkPlan(let slug, _):
            [slug.map { "slug: \($0)" }].compactMap { $0 }
        case .viewAll(let sectionID, _):
            ["rail id: \(sectionID)"]
        case .signInRequired:
            ["Sign-in isn't available in this build."]
        default:
            []
        }
    }

    private static func symbol(for route: AppRoute) -> String {
        switch route {
        case .content(_, _, let kind):
            switch kind {
            case .live: "dot.radiowaves.left.and.right"
            case .audio: "music.note"
            default: "play.rectangle"
            }
        case .channel: "tv"
        case .bulkPlan: "bag"
        case .viewAll: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .voiceSearch: "mic"
        case .notifications: "bell"
        case .menu: "line.3.horizontal"
        case .signInRequired: "person.badge.key"
        }
    }
}
