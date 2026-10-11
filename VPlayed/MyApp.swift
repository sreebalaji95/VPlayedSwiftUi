import SwiftUI

@main struct MyApp: App {
    init() {
        BrandFonts.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
