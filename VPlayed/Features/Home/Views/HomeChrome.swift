import SwiftUI

/// Home's top bar, built from system toolbar items so it is Liquid Glass on iOS 26:
/// menu on the leading side, the brand wordmark centred, notifications on the trailing side.
struct HomeToolbar: ToolbarContent {
    let openRoute: RouteAction

    var body: some ToolbarContent {
        ToolbarItem(placement: Self.leading) {
            Button { openRoute(.menu) } label: {
                Label(L10n.shared(.menuOpen), systemImage: "line.3.horizontal")
            }
        }
        logo
        ToolbarItem(placement: Self.trailing) {
            Button { openRoute(.notifications) } label: {
                Label(L10n.shared(.navNotifications), systemImage: "bell")
            }
        }
    }

    private static let leading = ToolbarItemPlacement.topBarLeading
    private static let trailing = ToolbarItemPlacement.topBarTrailing

    /// The wordmark floats on its own, without the glass capsule toolbar items get by default.
    @ToolbarContentBuilder
    private var logo: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .principal) { BrandWordmark() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { BrandWordmark() }
        }
    }
}
