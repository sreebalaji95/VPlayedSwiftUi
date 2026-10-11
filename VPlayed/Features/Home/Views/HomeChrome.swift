import SwiftUI

/// Home's top bar, built from system toolbar items so it is Liquid Glass on iOS / macOS 26:
/// menu on the leading side, the VPlayed wordmark centred, notifications on the trailing side.
struct HomeToolbar: ToolbarContent {
    let openRoute: RouteAction

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { openRoute(.menu) } label: {
                Label("Menu", systemImage: "line.3.horizontal")
            }
        }
        logo
        ToolbarItem(placement: .primaryAction) {
            Button { openRoute(.notifications) } label: {
                Label("Notifications", systemImage: "bell")
            }
        }
    }

    /// The wordmark floats on its own, without the glass capsule toolbar items get by default.
    @ToolbarContentBuilder
    private var logo: some ToolbarContent {
        #if os(visionOS)
        ToolbarItem(placement: .principal) { wordmark }
        #else
        if #available(iOS 26, macOS 26, *) {
            ToolbarItem(placement: .principal) { wordmark }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { wordmark }
        }
        #endif
    }

    private var wordmark: some View {
        // Same asset as the splash, so it has the light and dark variants.
        Image(.splashLogo)
            .resizable()
            .scaledToFit()
            .frame(height: Theme.Layout.headerLogoHeight)
            .accessibilityLabel("VPlayed")
            .accessibilityAddTraits(.isHeader)
    }
}
