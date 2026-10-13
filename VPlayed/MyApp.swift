import SwiftUI

@main struct MyApp: App {
    /// Launch-time configuration (common settings, geo token), fetched once per process.
    @State private var startup: AppStartup
    /// The signed-in, guest or signed-out session, restored from the Keychain.
    @State private var account = AccountStore()

    init() {
        BrandFonts.registerBundledFonts()
        let startup = AppStartup()
        _startup = State(initialValue: startup)
        startup.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(startup: startup, account: account)
        }
    }
}
