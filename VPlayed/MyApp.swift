import SwiftUI

@main struct MyApp: App {
    /// Starts Firebase at launch (phone and Google sign-in).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                // Google sign-in and phone sign-in's reCAPTCHA check return here.
                .onOpenURL { AuthURLHandler.handle($0) }
        }
    }
}
