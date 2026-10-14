import Foundation

/// Data source for the launch-time configuration calls.
nonisolated protocol StartupServicing: Sendable {
    func commonSettings() async throws -> CommonSettings
    /// Looks up the public IP address, then its geo token. Nil when the server returns no token.
    func geoLookup() async throws -> GeoLookup?
}

/// The services the app uses: the Kotlin shared layer (`SharedStartupService`). Tests pass mocks.
nonisolated enum StartupServices {
    static func live() -> any StartupServicing {
        SharedStartupService()
    }
}
