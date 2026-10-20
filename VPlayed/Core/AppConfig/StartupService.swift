import Foundation

/// Data source for the launch-time configuration calls.
nonisolated protocol StartupServicing: Sendable {
    func commonSettings() async throws -> CommonSettings
    /// Looks up the public IP address, then its geo token. Nil when the server returns no token.
    func geoLookup() async throws -> GeoLookup?
    /// Keeps a guest session whenever nobody is signed in and the common settings allow guests.
    func startGuestSessions()
    /// Loads the languages the user can pick (`mediaview/api/v1/language`) into the shared
    /// `SupportedLanguagesStore`, which `LanguageStore` watches. Failures keep the built-in list.
    func loadLanguages() async
}

extension StartupServicing {
    /// Mocks start no guest sessions.
    func startGuestSessions() {}
    /// Mocks keep the built-in language list.
    nonisolated func loadLanguages() async {}
}

/// The services the app uses: the Kotlin shared layer (`SharedStartupService`). Tests pass mocks.
nonisolated enum StartupServices {
    static func live() -> any StartupServicing {
        SharedStartupService()
    }
}
