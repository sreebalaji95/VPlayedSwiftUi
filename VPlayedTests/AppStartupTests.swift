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

    init(
        settings: Result<CommonSettings, any Error>,
        ip: Result<String, any Error> = .success("203.0.113.7"),
        token: Result<String?, any Error>,
        geoDelay: Duration? = nil
    ) {
        self.settings = settings
        self.ip = ip
        self.token = token
        self.geoDelay = geoDelay
    }

    func calls(_ name: String) -> Int { lock.withLock { counts[name, default: 0] } }
    var ipsRequested: [String] { lock.withLock { requestedIPs } }

    func commonSettings() async throws -> CommonSettings {
        lock.withLock { counts["common", default: 0] += 1 }
        return try settings.get()
    }

    func publicIPAddress() async throws -> String {
        lock.withLock { counts["ip", default: 0] += 1 }
        return try ip.get()
    }

    func geoToken(forIP ip: String) async throws -> String? {
        lock.withLock {
            counts["geo", default: 0] += 1
            requestedIPs.append(ip)
        }
        if let geoDelay { try await Task.sleep(for: geoDelay) }
        return try token.get()
    }
}

private func settings(_ json: String) throws -> CommonSettings {
    try JSONDecoder().decode(CommonSettings.self, from: Data(json.utf8))
}

private func fixtureToken() throws -> String {
    try #require(try Fixture.payload("geo-data", as: GeoTokenResponse.self).geoToken)
}

private func headers(_ session: SessionStore) async -> [String: String] {
    await RequestHeaders(session: session, deviceID: "test-device", appVersion: "9.9.9", languageCode: { "en" }).values()
}

@MainActor
struct CommonSettingsDecodingTests {
    @Test func decodesDevResponse() throws {
        let settings = try Fixture.payload("common", as: CommonSettings.self)

        #expect(settings.isRTLAllowed == true)
        #expect(settings.isPiPAllowed == true)
        #expect(settings.isCastingAllowed == true)
        #expect(settings.isScreenRecordingAllowed == true)
        #expect(settings.isGuestUser == false)
        #expect(settings.contentLibrary == .vodDrama)
        #expect(settings.verificationMethod == .email)
        #expect(settings.isIAPEnabled == false)
        #expect(settings.isAppStoreCTAChange == false)
        let update = try #require(settings.update)
        #expect(update.isForceUpdateEnabled == false)
        #expect(update.minimumVersion == nil)
    }

    @Test func toleratesMixedTypesAndMissingKeys() throws {
        let decoded = try settings(#"{"content_library":"2","otp_verfied":"phone","rtl":0,"is_iap_enabled":1}"#)

        #expect(decoded.contentLibrary == .drama)
        #expect(decoded.verificationMethod == .phone)
        #expect(decoded.isRTLAllowed == false)
        #expect(decoded.isIAPEnabled == true)
        #expect(decoded.isPiPAllowed == nil)
        #expect(decoded.update == nil)

        let empty = try settings("{}")
        #expect(empty.contentLibrary == .vodDrama)
        #expect(empty.verificationMethod == .email)
        #expect(empty.isRTLAllowed == nil)
    }

    @Test func keepsOnlyTheIOSUpdateDetails() throws {
        let android = try settings(#"{"force_update_details":{"platform":"android","force_update":true}}"#)
        #expect(android.update == nil)

        let ios = try settings(#"{"force_update_details":{"platform":"iOS","force_update":true,"minimum_version":"2.1.0"}}"#)
        #expect(ios.update?.isForceUpdateEnabled == true)
        #expect(ios.update?.minimumVersion == "2.1.0")
    }

    @Test func decodesGeoTokenPayload() throws {
        let info = try #require(GeoInfo(token: try fixtureToken()))

        #expect(info.countryCode == "IN")
        #expect(info.currency == "INR")
        #expect(info.timezone == "Asia/Kolkata")
        #expect(GeoInfo(token: "not base64!") == nil)
        #expect(GeoInfo(token: Data("plain text".utf8).base64EncodedString()) == nil)
    }

    @Test func nullGeoTokenDecodesAsNil() throws {
        let response = try JSONDecoder().decode(GeoTokenResponse.self, from: Data(#"{"geo_token":null}"#.utf8))
        #expect(response.geoToken == nil)
    }

    @Test func endpointsMatchTheUIKitPaths() throws {
        let base = APIEnvironment.development.apiBaseURL
        #expect(try Endpoint.common.url(relativeTo: base).absoluteString == "https://api-devgs.vplayed.com/mediaview/api/v1/common")
        #expect(try Endpoint.geoData(ip: "203.0.113.7").url(relativeTo: base).absoluteString
            == "https://api-devgs.vplayed.com/mediaview/api/v1/common/geo-data/203.0.113.7")
    }
}

@MainActor
struct AppStartupTests {
    @Test func startRunsEachCallOnceAndSetsTheGeoHeader() async throws {
        let token = try fixtureToken()
        let service = MockStartupService(settings: .success(try Fixture.payload("common", as: CommonSettings.self)), token: .success(token))
        let session = SessionStore()
        let startup = AppStartup(service: service, session: session)

        startup.start()
        startup.start()
        await startup.waitForGeoToken(upTo: .seconds(5))
        startup.start()
        while startup.settings == nil { await Task.yield() }

        #expect(service.calls("common") == 1)
        #expect(service.calls("ip") == 1)
        #expect(service.calls("geo") == 1)
        #expect(service.ipsRequested == ["203.0.113.7"])
        #expect(await headers(session)["X-Bearer-Token"] == token)
        #expect(startup.geoInfo?.countryCode == "IN")
        #expect(startup.isRTLAllowed)
        #expect(!startup.forcesDarkMode)
    }

    @Test func failuresAndNullTokenLeaveDefaults() async throws {
        let service = MockStartupService(settings: .failure(APIError.network(code: -1009)), token: .success(nil))
        let session = SessionStore()
        let startup = AppStartup(service: service, session: session)

        startup.start()
        await startup.waitForGeoToken(upTo: .seconds(5))

        #expect(service.calls("geo") == 1)
        #expect(await headers(session)["X-Bearer-Token"] == nil)
        #expect(startup.geoInfo == nil)
        #expect(startup.settings == nil)
        #expect(startup.isRTLAllowed)
        #expect(!startup.forcesDarkMode)
    }

    @Test func ipLookupFailureSkipsGeoData() async throws {
        let service = MockStartupService(settings: .success(try settings("{}")), ip: .failure(APIError.network(code: -1001)), token: .success("unused"))
        let startup = AppStartup(service: service, session: SessionStore())

        startup.start()
        await startup.waitForGeoToken(upTo: .seconds(5))

        #expect(service.calls("geo") == 0)
    }

    @Test func waitGivesUpAtTheLimit() async throws {
        let service = MockStartupService(settings: .success(try settings("{}")), token: .success("late"), geoDelay: .seconds(30))
        let startup = AppStartup(service: service, session: SessionStore())
        startup.start()

        let elapsed = await ContinuousClock().measure {
            await startup.waitForGeoToken(upTo: .milliseconds(100))
        }

        #expect(elapsed < .seconds(5))
    }

    @Test func waitReturnsAtOnceWhenNotStarted() async throws {
        let startup = AppStartup(service: MockStartupService(settings: .success(try settings("{}")), token: .success(nil), geoDelay: .seconds(30)))
        let elapsed = await ContinuousClock().measure {
            await startup.waitForGeoToken(upTo: .seconds(30))
        }
        #expect(elapsed < .seconds(1))
    }

    @Test(arguments: [("0", false), ("1", false), ("2", true)])
    func dramaForcesDarkMode(library: String, dark: Bool) async throws {
        let service = MockStartupService(settings: .success(try settings(#"{"content_library":\#(library),"rtl":false}"#)), token: .success(nil))
        let startup = AppStartup(service: service, session: SessionStore())

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

    @Test func homeWaitsForPrepareBeforeItsFirstRequest() async throws {
        let service = MockHomeService(pages: [1: .success(HomeFeedPage(sections: [], nextPage: nil))])
        var callsDuringPrepare: [Int]?
        let model = HomeViewModel(service: service, prepare: { callsDuringPrepare = service.pageCalls })

        await model.loadIfNeeded()
        await model.refresh()

        #expect(callsDuringPrepare == [])
        #expect(service.pageCalls == [1, 1])
    }
}
