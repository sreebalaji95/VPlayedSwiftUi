import Foundation

/// Data source for the launch-time configuration calls.
nonisolated protocol StartupServicing: Sendable {
    func commonSettings() async throws -> CommonSettings
    /// Looks up the public IP address, then its geo token. Nil when the server returns no token.
    func geoLookup() async throws -> GeoLookup?
}

/// The services the app uses: the Kotlin shared layer where it is linked, else the Swift implementation.
nonisolated enum StartupServices {
    static func live() -> any StartupServicing {
        #if canImport(Shared)
        SharedStartupService()
        #else
        StartupService()
        #endif
    }
}

/// The Swift implementation, used on visionOS (see `StartupServices.live()`); replaced by
/// `SharedStartupService` elsewhere and removed once visionOS is settled (Phase 7).
nonisolated struct StartupService: StartupServicing {
    var client: APIClient = .shared
    var session: URLSession = .shared

    /// The UIKit app looks the address up here before asking for a geo token
    /// (`SplashScreenViewController.getBearerToken`).
    private static let ipLookupURL = URL(string: "https://api.ipify.org/?format=json")!

    private struct IPLookup: Decodable {
        var ip: String?
    }

    func commonSettings() async throws -> CommonSettings {
        try await client.get(.common, as: CommonSettings.self)
    }

    func geoLookup() async throws -> GeoLookup? {
        let ip = try await publicIPAddress()
        guard let token = try await geoToken(forIP: ip), !token.isEmpty else { return nil }
        return GeoLookup(token: token, info: GeoInfo(token: token))
    }

    /// The device's public IP address, which the geo-data endpoint takes as its last path segment.
    /// Not a VPlayed API, so it has no envelope and doesn't go through `APIClient`.
    @concurrent
    func publicIPAddress() async throws -> String {
        var request = URLRequest(url: Self.ipLookupURL)
        request.timeoutInterval = 15
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw APIError.network(code: error.code.rawValue)
        }
        guard let ip = try? JSONDecoder().decode(IPLookup.self, from: data).ip?
            .trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty else {
            throw APIError.decoding("No `ip` in the address lookup")
        }
        return ip
    }

    func geoToken(forIP ip: String) async throws -> String? {
        try await client.get(.geoData(ip: ip), as: GeoTokenResponse.self).geoToken
    }
}
