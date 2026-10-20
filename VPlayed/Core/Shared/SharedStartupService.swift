import Foundation
// Kotlin classes are not Sendable; the repositories are thread-safe and only used through this adapter.
@preconcurrency import Shared

/// The launch-time calls through the Kotlin Multiplatform shared layer, the same code AndroidJP uses:
/// `mediaview/api/v1/common` (`SharedGraph.commonSettingsRepository`) and the public IP → geo token
/// lookup (`SharedGraph.geoRepository`, decision D18), which keeps the token in the graph's `GeoStore`
/// for every request. `AppStartup` decides when they run.
nonisolated final class SharedStartupService: StartupServicing, @unchecked Sendable {
    private let settingsRepository: CommonSettingsRepository
    private let geoRepository: GeoRepository
    private let guestSessions: GuestSessionKeeper

    init(graph: SharedGraph = SharedLayer.graph) {
        settingsRepository = graph.commonSettingsRepository
        geoRepository = graph.geoRepository
        guestSessions = graph.guestSessionKeeper
    }

    /// The UIKit app's automatic guest session (`checkIfUserLoggedIn`), on the shared rule: it reads
    /// the settings `commonSettings()` loads into the graph's `CommonSettingsStore`.
    func startGuestSessions() {
        guestSessions.start()
    }

    func commonSettings() async throws -> CommonSettings {
        let result = try await settingsRepository.load()
        if let failure = result as? DataResultFailure { throw APIError(failure.error) }
        guard let settings = (result as? DataResultSuccess<Shared.CommonSettings>)?.data else {
            throw APIError.decoding("Unknown settings result")
        }
        return CommonSettings(settings)
    }

    /// A refresh that fails keeps the previous token in the shared store; like the UIKit app, launch
    /// then carries on without one.
    func geoLookup() async throws -> GeoLookup? {
        let outcome = try await geoRepository.refresh()
        switch outcome {
        case .success:
            let state = geoRepository.store.current
            guard let token = state.geoToken else { return nil }
            return GeoLookup(token: token, info: state.info.map(GeoInfo.init))
        case .transientFailure:
            throw APIError.network(code: URLError.Code.cannotConnectToHost.rawValue)
        default:
            // An invalid address or no token in the answer.
            return nil
        }
    }
}

extension CommonSettings {
    /// The shared settings in this app's type (same keys and UIKit defaults).
    nonisolated init(_ settings: Shared.CommonSettings) {
        let library: ContentLibrary = switch settings.contentLibrary {
        case .vod: .vod
        case .drama: .drama
        default: .vodDrama
        }
        let method: VerificationMethod = switch settings.verificationMethod {
        case .phone: .phone
        case .mobile: .mobile
        default: .email
        }
        self.init(
            isRTLAllowed: settings.isRtlAllowed?.boolValue,
            isPiPAllowed: settings.isPipAllowed?.boolValue,
            isCastingAllowed: settings.isCastingAllowed?.boolValue,
            isScreenRecordingAllowed: settings.isScreenRecordingAllowed?.boolValue,
            isGuestUser: settings.isGuestUser?.boolValue,
            contentLibrary: library,
            verificationMethod: method,
            isIAPEnabled: settings.isIapEnabled,
            isAppStoreCTAChange: settings.isAppStoreCtaChange,
            update: settings.update.map {
                UpdateDetails(
                    isForceUpdateEnabled: $0.isForceUpdateEnabled,
                    minimumVersion: $0.minimumVersion,
                    forceUpdateMessage: $0.forceUpdateMessage,
                    isSoftUpdateEnabled: $0.isSoftUpdateEnabled,
                    latestVersion: $0.latestVersion,
                    softUpdateMessage: $0.softUpdateMessage
                )
            }
        )
    }
}

extension GeoInfo {
    nonisolated init(_ info: Shared.GeoInfo) {
        self.init(
            country: info.country,
            countryCode: info.countryCode,
            currency: info.currency,
            region: info.region,
            regionName: info.regionName,
            city: info.city,
            timezone: info.timezone
        )
    }
}
