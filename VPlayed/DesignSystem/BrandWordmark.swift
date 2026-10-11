import SwiftUI

/// The wordmark at header height, for the Home toolbar and the menu header. It is the same
/// `SplashLogo` asset the launch screen and the splash draw, so it has light and dark variants.
struct BrandWordmark: View {
    var body: some View {
        Image(.splashLogo)
            .resizable()
            .scaledToFit()
            .frame(height: Theme.Layout.headerLogoHeight)
            .accessibilityLabel(Text(verbatim: Brand.name))
            .accessibilityAddTraits(.isHeader)
    }
}
