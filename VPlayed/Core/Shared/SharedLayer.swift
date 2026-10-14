#if canImport(Shared)
import Foundation
import os
// Kotlin classes are not Sendable; they are only used through the main-actor adapters below.
@preconcurrency import Shared

/// Entry point to the Kotlin Multiplatform shared layer (`../kmp`, linked through the local
/// `SharedKit` package). One `SharedGraph` per process, built from the same configuration the
/// native networking uses. Kotlin/Native has no visionOS target, so this file and every use of
/// `Shared` sit behind `#if canImport(Shared)`; visionOS keeps the native Swift implementations.
///
/// Phase 2 (foundation): nothing in the app calls the graph yet, so behaviour is unchanged.
/// Features move to it phase by phase (see `KMP_PLANNING/KMP_MIGRATION_PLAN.md`).
nonisolated enum SharedLayer {
    /// The app's graph, created on first use.
    static let graph: SharedGraph = makeGraph()

    /// Builds a graph. Tests pass their own engine factory (e.g. one using a `URLProtocol` stub).
    static func makeGraph(
        environment: APIEnvironment = .current,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
        transportKey: String = CryptoJSAES.authPassphrase,
        deviceInfo: any DeviceInfo = IOSSharedDeviceInfo(),
        engineFactory: (() -> any Ktor_client_coreHttpClientEngine)? = nil
    ) -> SharedGraph {
        SharedGraph(
            config: sharedConfig(environment: environment, appVersion: appVersion, transportKey: transportKey),
            platform: PlatformDependencies(
                deviceInfo: deviceInfo,
                logger: IOSSharedLogger(),
                engineFactory: engineFactory ?? { HttpEngine_appleKt.createDarwinEngine(configure: configureSession) },
                cryptoPrimitives: CryptoPrimitives_appleKt.platformCryptoPrimitives()
            )
        )
    }

    /// The shared layer's configuration for an environment: same hosts as `APIEnvironment`, same
    /// app version and transport key as the native requests.
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

    /// The same session tuning as `APIClient.makeSession()`; timeouts come from `SharedConfig`.
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

/// Device facts for shared requests, from the same sources as `RequestHeaders` and `AuthService`.
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

    /// Read per request, so an in-app language switch applies immediately (as in `RequestHeaders`).
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
#endif
