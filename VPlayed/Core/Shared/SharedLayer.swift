import Foundation
import os
// Kotlin classes are not Sendable; they are only used through the main-actor adapters below.
@preconcurrency import Shared

/// Entry point to the Kotlin Multiplatform shared layer (`../kmp`, linked through the local
/// `SharedKit` package). One `SharedGraph` per process. Every backend call goes through it: sign-in
/// (`SharedAuthService`, `SharedLoginViewModel`), Home (`SharedHomeViewModel`), Movies
/// (`SharedMoviesService`), the launch calls (`SharedStartupService`) and the session (`sessions`,
/// behind `AccountStore`). The app has no other network stack. On Mac and Apple Vision Pro it runs
/// as the iPad app ("Designed for iPad").
nonisolated enum SharedLayer {
    /// The app's graph, created on first use.
    static let graph: SharedGraph = makeGraph()

    /// The signed-in or guest session, stored in the Keychain item the app has always used
    /// (`KeychainSecureStore`). Shared requests send its tokens as `Authorization` and `profile_id`.
    static let sessions = SessionManager(store: DispatchingSecureStore(store: KeychainSecureStore()))

    /// The passphrase the UIKit app encrypts auth payloads with (`getEmailEncrypted`). It is not in
    /// source control: `VPLAYED_TRANSPORT_KEY` in the git-ignored `Config/Secrets.xcconfig` reaches the
    /// app through the `VPlayedTransportKey` Info.plist entry. Empty when the build has none (sign-in
    /// then reports an error and sends nothing).
    static let transportKey: String = Bundle.main.object(forInfoDictionaryKey: "VPlayedTransportKey") as? String ?? ""

    /// Builds a graph. Tests pass their own engine factory (e.g. one using a `URLProtocol` stub).
    static func makeGraph(
        environment: APIEnvironment = .current,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
        transportKey: String = SharedLayer.transportKey,
        deviceInfo: any DeviceInfo = IOSSharedDeviceInfo(),
        sessions: SessionManager = sessions,
        engineFactory: (() -> any Ktor_client_coreHttpClientEngine)? = nil
    ) -> SharedGraph {
        SharedGraph(
            config: sharedConfig(environment: environment, appVersion: appVersion, transportKey: transportKey),
            platform: PlatformDependencies(
                deviceInfo: deviceInfo,
                logger: IOSSharedLogger(),
                engineFactory: engineFactory ?? { HttpEngine_appleKt.createDarwinEngine(configure: configureSession) },
                cryptoPrimitives: CryptoPrimitives_appleKt.platformCryptoPrimitives()
            ),
            sessionManager: sessions
        )
    }

    /// The shared layer's configuration for an environment: same hosts as `APIEnvironment`, same
    /// app version and transport key.
    static func sharedConfig(environment: APIEnvironment, appVersion: String, transportKey: String) -> SharedConfig {
        SharedConfig(
            environment: serverEnvironment(for: environment),
            serverUrl: environment.apiBaseURL.absoluteString,
            imageBaseUrl: environment.imageBaseURL.absoluteString,
            loggingEnabled: isDebugBuild,
            appVersion: appVersion,
            platform: .ios,
            transportKey: transportKey,
            requestTimeoutMillis: SharedConfig.companion.DEFAULT_REQUEST_TIMEOUT_MILLIS,
            connectTimeoutMillis: SharedConfig.companion.DEFAULT_CONNECT_TIMEOUT_MILLIS
        )
    }

    /// The environment id for `APIEnvironment`'s hosts (Demo is the UIKit app's PROD build).
    static func serverEnvironment(for environment: APIEnvironment) -> ServerEnvironment {
        switch environment.apiBaseURL {
        case APIEnvironment.qa.apiBaseURL: .qa
        case APIEnvironment.staging.apiBaseURL: .staging
        case APIEnvironment.demo.apiBaseURL: .demo
        default: .development
        }
    }

    /// Connection limit and response cache for the Darwin engine; timeouts come from `SharedConfig`.
    private static func configureSession(_ configuration: URLSessionConfiguration) {
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 32 << 20)
    }

    /// Request logging only in debug configurations (`DebugDev`, `DebugQa`, …), like Android's dev/qa builds.
    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// Device facts for the backend headers: the Keychain device id, the model identifier and the in-app language.
/// Called by Kotlin from background threads, so it is nonisolated and reads only thread-safe values.
nonisolated final class IOSSharedDeviceInfo: NSObject, DeviceInfo, @unchecked Sendable {
    private let languageCodeProvider: @Sendable () -> String

    let deviceId: String?
    let deviceName: String

    init(
        deviceId: String? = DeviceID.current,
        deviceName: String = DeviceModel.identifier,
        languageCode: @escaping @Sendable () -> String = { AppLanguage.current.rawValue }
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        languageCodeProvider = languageCode
    }

    /// Read per request, so an in-app language switch applies immediately.
    func languageCode() -> String { languageCodeProvider() }
}

/// Shared-layer log lines in the unified log, category `Shared`. Messages never contain secrets.
nonisolated final class IOSSharedLogger: NSObject, SharedLogger, @unchecked Sendable {
    private let log = Logger(subsystem: "com.contus.vplayed", category: "Shared")

    func debug(tag: String, message: String) {
        log.debug("[\(tag, privacy: .public)] \(message, privacy: .public)")
    }

    func info(tag: String, message: String) {
        log.info("[\(tag, privacy: .public)] \(message, privacy: .public)")
    }

    func error(tag: String, message: String, throwable: KotlinThrowable?) {
        log.error("[\(tag, privacy: .public)] \(message, privacy: .public)")
    }
}
