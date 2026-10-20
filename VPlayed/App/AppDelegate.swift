import UIKit

/// The UIKit app delegate, as Firebase's SwiftUI setup asks for: Firebase starts in
/// `didFinishLaunching`, where its app-delegate proxy (APNs for phone sign-in) can attach.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // `FirebaseApp.configure()`, from this build's Firebase settings or the bundled
        // GoogleService-Info.plist; does nothing without either.
        FirebaseBootstrap.configure()
        return true
    }
}
