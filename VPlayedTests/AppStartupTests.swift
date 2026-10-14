import Foundation
import Testing
@testable import VPlayed

/// Scripted `StartupServicing` that counts calls. Development-only; never used by the app.
final class MockStartupService: StartupServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let settings: Result<CommonSettings, any Error>
    private let ip: Result<String, any Error>
    private let token: Result<String?, any Error>
    private let geoDelay: Duration?
    private var counts: [String: Int] = [:]
    private var requestedIPs: [String] = []

    private let info: GeoInfo?

    init(
        settings: Result<CommonSettings, any Error>,
        ip: Result<String, any Error> = .success("203.0.113.7"),
        token: Result<String?, any Error>,
        info: GeoInfo? = GeoInfo(countryCode: "IN", currency: "INR"),
        geoDelay: Duration? = nil
    ) {
        self.settings = settings
        self.ip = ip
        self.token = token
        self.info = info
        self.geoDelay = geoDelay
    }

    func calls(_ name: String) -> Int { lock.withLock { counts[name, default: 0] } }
    var ipsRequested: [String] { lock.withLock { requestedIPs } }

    func commonSettings() async throws -> CommonSettings {
        lock.withLock { counts["common", default: 0] += 1 }
        return try settings.get()
    }

    /// The IP lookup then the token, counted separately, like the shared refresh.
    func geoLookup() async throws -> GeoLookup? {
        lock.withLock { counts["ip", default: 0] += 1 }
        let ip = try ip.get()
        lock.withLock {
            counts["geo", default: 0] += 1
            requestedIPs.append(ip)
        }
        if let geoDelay { try await Task.sleep(for: geoDelay) }
        guard let token = try token.get(), !token.isEmpty else { return nil }
        return GeoLookup(token: token, info: info)
    }
}

private let devSettings = CommonSettings(isRTLAllowed: true, isPiPAllowed: true, isCastingAllowed: true, isScreenRecordingAllowed: true, isGuestUser: false)

@MainActor
struct AppStartupTests {
    @Test func startRunsEachCallOnceAndKeepsTheLocation() async throws {
        let service = MockStartupService(settings: .success(devSettings), token: .success("geo-token"))
        let startup = AppStartup(service: service)

        startup.start()
        startup.start()
        await startup.waitForGeoToken(upTo: .seconds(5))
        startup.start()
        while startup.settings == nil { await Task.yield() }

        #expect(service.calls("common") == 1)
        #expect(service.calls("ip") == 1)
        #expect(service.calls("geo") == 1)
        #expect(service.ipsRequested == ["203.0.113.7"])
        #expect(startup.geoInfo?.countryCode == "IN")
        #expect(startup.isRTLAllowed)
        #expect(!startup.forcesDarkMode)
    }

    @Test func failuresAndNullTokenLeaveDefaults() async throws {
        let service = MockStartupService(settings: .failure(APIError.network(code: -1009)), token: .success(nil))
        let startup = AppStartup(service: service)

        startup.start()
        await startup.waitForGeoToken(upTo: .seconds(5))

        #expect(service.calls("geo") == 1)
        #expect(startup.geoInfo == nil)
        #expect(startup.settings == nil)
        #expect(startup.isRTLAllowed)
        #expect(!startup.forcesDarkMode)
    }

    @Test func ipLookupFailureSkipsGeoData() async throws {
        let service = MockStartupService(settings: .success(CommonSettings()), ip: .failure(APIError.network(code: -1001)), token: .success("unused"))
        let startup = AppStartup(service: service)

        startup.start()
        await startup.waitForGeoToken(upTo: .seconds(5))

        #expect(service.calls("geo") == 0)
    }

    @Test func waitGivesUpAtTheLimit() async throws {
        let service = MockStartupService(settings: .success(CommonSettings()), token: .success("late"), geoDelay: .seconds(30))
        let startup = AppStartup(service: service)
        startup.start()

        let elapsed = await ContinuousClock().measure {
            await startup.waitForGeoToken(upTo: .milliseconds(100))
        }

        #expect(elapsed < .seconds(5))
    }

    @Test func waitReturnsAtOnceWhenNotStarted() async throws {
        let startup = AppStartup(service: MockStartupService(settings: .success(CommonSettings()), token: .success(nil), geoDelay: .seconds(30)))
        let elapsed = await ContinuousClock().measure {
            await startup.waitForGeoToken(upTo: .seconds(30))
        }
        #expect(elapsed < .seconds(1))
    }

    @Test(arguments: [(CommonSettings.ContentLibrary.vodDrama, false), (.vod, false), (.drama, true)])
    func dramaForcesDarkMode(library: CommonSettings.ContentLibrary, dark: Bool) async throws {
        let service = MockStartupService(settings: .success(CommonSettings(isRTLAllowed: false, contentLibrary: library)), token: .success(nil))
        let startup = AppStartup(service: service)

        startup.start()
        while startup.settings == nil { await Task.yield() }

        #if QA
        #expect(!startup.forcesDarkMode)
        #else
        #expect(startup.forcesDarkMode == dark)
        #endif
        #expect(!startup.isRTLAllowed)
    }

    @Test func rtlCanBeTurnedOffForArabic() {
        let store = LanguageStore()
        defer { store.isRTLAllowed = true }

        store.isRTLAllowed = false
        #expect(!store.isRightToLeft)
        store.isRTLAllowed = true
        #expect(store.isRightToLeft == store.language.isRightToLeft)
    }
}
