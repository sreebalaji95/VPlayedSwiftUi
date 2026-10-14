import Foundation
import Observation
import os

/// Runs the launch-time configuration calls once per process and holds what they return.
/// `MyApp` owns it and calls `start()` from its initializer, so view updates, navigation and
/// language switches never fetch again.
///
/// The two calls are independent and run concurrently, as in the UIKit app:
/// - **Common** (`SceneDelegate.getCommonKeys`): feature flags, payment flags and update details.
/// - **Geo** (`SplashScreenViewController.getBearerToken`): looks up the public IP, then fetches
///   its geo token. The shared lookup keeps the token in the graph's `GeoStore`, so every later
///   request sends it as `X-Bearer-Token`.
///
/// Both calls run on the Kotlin shared layer (`SharedStartupService`, decision D18: the refresh is
/// shared, the app decides when it runs).
///
/// Failures are logged and otherwise ignored, as in the UIKit app: the defaults apply and launch
/// carries on.
@Observable
final class AppStartup {
    /// `nil` until the common API answers, or for good if it fails.
    private(set) var settings: CommonSettings?
    /// The location encoded in the geo token, once there is one.
    private(set) var geoInfo: GeoInfo?

    /// The server can turn right-to-left layout off; only an explicit `false` does (UIKit rule).
    var isRTLAllowed: Bool { settings?.isRTLAllowed != false }

    /// Drama catalogues are dark-only, except in QA builds (UIKit rule).
    var forcesDarkMode: Bool {
        #if QA
        false
        #else
        settings?.contentLibrary == .drama
        #endif
    }

    @ObservationIgnored private let service: any StartupServicing
    @ObservationIgnored private var commonTask: Task<Void, Never>?
    @ObservationIgnored private var geoTask: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.contus.vplayed", category: "Startup")

    init(service: any StartupServicing = StartupServices.live()) {
        self.service = service
    }

    /// Starts both calls. Later calls do nothing.
    func start() {
        guard commonTask == nil else { return }
        commonTask = Task { await loadCommonSettings() }
        geoTask = Task { await loadGeoToken() }
    }

    /// Waits until the geo step has finished, or `limit` has passed, whichever comes first.
    /// Returns at once if `start()` was never called.
    func waitForGeoToken(upTo limit: Duration) async {
        guard let geoTask else { return }
        // Not a task group: it would wait for both children, and `Task.value` ignores cancellation.
        let (finished, signal) = AsyncStream<Never>.makeStream()
        let waiter = Task { await geoTask.value; signal.finish() }
        let timer = Task { try? await Task.sleep(for: limit); signal.finish() }
        for await _ in finished {}
        // The geo step itself carries on after a timeout.
        waiter.cancel()
        timer.cancel()
    }

    private func loadCommonSettings() async {
        do {
            let settings = try await service.commonSettings()
            self.settings = settings
            Self.log.info("Common settings loaded (content library \(settings.contentLibrary.rawValue), RTL \(self.isRTLAllowed))")
        } catch {
            Self.log.error("Common settings failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadGeoToken() async {
        do {
            guard let lookup = try await service.geoLookup() else {
                Self.log.info("Geo token skipped: the server returned none")
                return
            }
            geoInfo = lookup.info
            Self.log.info("Geo token set (country \(self.geoInfo?.countryCode ?? "unknown", privacy: .public))")
        } catch {
            Self.log.error("Geo token failed: \(String(describing: error), privacy: .public)")
        }
    }
}
