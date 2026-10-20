import Foundation
@preconcurrency import Shared
import Testing
@testable import VPlayed

/// Suites that script `RouteStubURLProtocol`'s backend run one test at a time.
@Suite(.serialized)
enum RoutedBackendTests {}

/// The shared layer wired to `RouteStubURLProtocol`.
enum RoutedBackend {
    static let host = APIEnvironment.development.apiBaseURL.host()!

    static func graph(language: String = "en") -> SharedGraph {
        SharedLayer.makeGraph(
            environment: .development,
            appVersion: "9.9.9",
            transportKey: "unit-test-passphrase",
            deviceInfo: IOSSharedDeviceInfo(deviceId: "test-device", deviceName: "iPhone17,3", languageCode: { language }),
            sessions: SessionManager(store: InMemorySecureStore()),
            engineFactory: {
                HttpEngine_appleKt.createDarwinEngine { $0.protocolClasses = [RouteStubURLProtocol.self] }
            }
        )
    }

    static func route(_ path: String, page: Int? = nil) -> String {
        host + "/" + path + (page.map { "?page=\($0)" } ?? "")
    }

    static func fixture(_ name: String) throws -> RouteStubURLProtocol.Answer {
        .json(status: 200, body: String(decoding: try Fixture.data(name), as: UTF8.self))
    }

    static let banners = route("mediaview/api/v1/homebanners")
    static func home(_ page: Int) -> String { route("mediaview/api/v1/home", page: page) }
    static let follow = route("studios/api/v1/follow_studio")
}

extension RoutedBackendTests {

    /// The Home model on the shared `HomeFeedController`. The feed rules themselves are
    /// tested in `../kmp` (`HomeFeedControllerTest`).
    @MainActor
    @Suite
    struct SharedHomeViewModelTests {
        private static let banner = #"{"statusCode":200,"response":{"data":[{"_id":"b1","master_details":{"_id":"c1","title":"Hero","sho_type":2}}]}}"#

        private static func page(_ rails: [String], next: Int?) -> RouteStubURLProtocol.Answer {
            let data = rails.map { id in
                #"{"_id":"\#(id)","title":"Rail \#(id)","type":1,"data":[{"_id":"\#(id)-1","title":"Item","sho_type":1}]}"#
            }
            return .json(status: 200, body: #"{"statusCode":200,"response":{"data":[\#(data.joined(separator: ","))],"next":\#(next.map(String.init) ?? "null")}}"#)
        }

        private static let channels = RouteStubURLProtocol.Answer.json(status: 200, body: #"""
            {"statusCode":200,"response":{"next":null,"data":[{"_id":"ch","title":"Channels","type":4,"data":[
            {"_id":"c1","name":"Chan","slug":"chan","follow_count":4,"is_followed":0}]}]}}
            """#)

        private func model(_ routes: [String: RouteStubURLProtocol.Answer], prepare: @escaping () async -> Void = {}) -> SharedHomeViewModel {
            RouteStubURLProtocol.reset(routes)
            return SharedHomeViewModel(graph: RoutedBackend.graph(), prepare: prepare)
        }

        @Test func initialLoadShowsBannersAndRailsAfterPrepare() async {
            var requestsDuringPrepare: Int?
            let model = model(
                [RoutedBackend.banners: .json(status: 200, body: Self.banner), RoutedBackend.home(1): Self.page(["a", "b"], next: 2)],
                prepare: { requestsDuringPrepare = RouteStubURLProtocol.captured.count }
            )
            #expect(model.phase == .idle)

            await model.loadIfNeeded()

            #expect(requestsDuringPrepare == 0)
            #expect(model.phase == .loaded)
            #expect(model.banners.map(\.title) == ["Hero"])
            #expect(model.banners.first?.kind == .series)
            #expect(model.sections.map(\.id) == ["a", "b"])
            #expect(model.hasMorePages)

            await model.loadIfNeeded()
            #expect(RouteStubURLProtocol.captured.count == 2, "Loads only once")
        }

        @Test func loadMoreAppendsUntilTheLastPage() async {
            let model = model([
                RoutedBackend.home(1): Self.page(["a"], next: 2),
                RoutedBackend.home(2): Self.page(["a", "b"], next: nil),
            ])
            await model.loadIfNeeded()

            await model.loadMoreIfNeeded()

            #expect(model.sections.map(\.id) == ["a", "b"])
            #expect(!model.hasMorePages)
            #expect(!model.isLoadingMore)
            #expect(!model.loadMoreFailed)
        }

        @Test func failuresShowTheErrorThenRetryRecovers() async {
            let model = model([RoutedBackend.home(1): .failure(.timedOut), RoutedBackend.banners: .failure(.timedOut)])
            await model.loadIfNeeded()

            #expect(model.phase == .failed(APIError.network(code: URLError.timedOut.rawValue).userMessage))

            RouteStubURLProtocol.set(RoutedBackend.home(1), Self.page(["a"], next: nil))
            await model.retry()
            #expect(model.phase == .loaded)
            #expect(model.sections.map(\.id) == ["a"])
        }

        @Test func emptyFeedShowsTheEmptyState() async {
            let model = model([RoutedBackend.home(1): Self.page([], next: nil)])
            await model.loadIfNeeded()
            #expect(model.phase == .empty)
        }

        @Test func refreshFailureKeepsContentAndShowsANotice() async {
            let model = model([RoutedBackend.home(1): Self.page(["a"], next: nil)])
            await model.loadIfNeeded()

            RouteStubURLProtocol.set(RoutedBackend.home(1), .json(status: 200, body: #"{"statusCode":500,"message":"Down for maintenance"}"#))
            await model.refresh()

            #expect(model.sections.map(\.id) == ["a"])
            #expect(await eventually { model.notice == "Down for maintenance" })
        }

        @Test func followingAChannelUpdatesTheCardAndShowsANotice() async throws {
            let model = model([RoutedBackend.home(1): Self.channels, RoutedBackend.follow: .json(status: 200, body: #"{"statusCode":201}"#)])
            await model.loadIfNeeded()
            guard case .channels(let channels) = model.sections.first?.content, let channel = channels.first else {
                Issue.record("Expected a channel rail")
                return
            }
            #expect(!model.isFollowing(channel))

            await model.setFollowing(true, channel: channel)

            guard case .channels(let updated) = model.sections.first?.content, let after = updated.first else {
                Issue.record("Expected a channel rail")
                return
            }
            #expect(model.isFollowing(after))
            #expect(model.followerCount(of: after) == 5)
            #expect(!model.isUpdatingFollow(after))
            #expect(await eventually { model.notice == L10n.string(.homeFollowedToast) })
            let request = try #require(RouteStubURLProtocol.captured.last)
            #expect(request.httpMethod == "POST")
        }

        @Test func failedFollowKeepsTheCardAsItWas() async {
            let model = model([RoutedBackend.home(1): Self.channels, RoutedBackend.follow: .failure(.notConnectedToInternet)])
            await model.loadIfNeeded()
            guard case .channels(let channels) = model.sections.first?.content, let channel = channels.first else {
                Issue.record("Expected a channel rail")
                return
            }

            await model.setFollowing(true, channel: channel)

            guard case .channels(let after) = model.sections.first?.content else { return }
            #expect(after == channels)
            #expect(await eventually { model.notice != nil })
        }
    }

    /// The launch calls through the shared layer.
    @MainActor
    @Suite
    struct SharedStartupServiceTests {
        private static let ipLookup = "api.ipify.org/"

        @Test func settingsComeFromTheDevResponse() async throws {
            RouteStubURLProtocol.reset([RoutedBackend.route("mediaview/api/v1/common"): try RoutedBackend.fixture("common")])
            let service = SharedStartupService(graph: RoutedBackend.graph())

            let settings = try await service.commonSettings()

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

        @Test func geoLookupReturnsTheTokenAndItsLocation() async throws {
            let fixture = try #require(try JSONSerialization.jsonObject(with: Fixture.data("geo-data")) as? [String: Any])
            let token = try #require((fixture["response"] as? [String: Any])?["geo_token"] as? String)
            RouteStubURLProtocol.reset([
                Self.ipLookup: .json(status: 200, body: #"{"ip":"203.0.113.7"}"#),
                RoutedBackend.route("mediaview/api/v1/common/geo-data/203.0.113.7"): try RoutedBackend.fixture("geo-data"),
            ])
            let service = SharedStartupService(graph: RoutedBackend.graph())

            let lookup = try #require(try await service.geoLookup())

            #expect(lookup.token == token)
            #expect(lookup.info?.countryCode == "IN")
            #expect(lookup.info?.currency == "INR")
            #expect(lookup.info?.timezone == "Asia/Kolkata")
        }

        @Test func geoFailuresThrowOrReturnNil() async throws {
            RouteStubURLProtocol.reset([Self.ipLookup: .failure(.notConnectedToInternet)])
            let service = SharedStartupService(graph: RoutedBackend.graph())
            await #expect(throws: APIError.self) { try await service.geoLookup() }

            RouteStubURLProtocol.reset([
                Self.ipLookup: .json(status: 200, body: #"{"ip":"203.0.113.7"}"#),
                RoutedBackend.route("mediaview/api/v1/common/geo-data/203.0.113.7"): .json(status: 200, body: #"{"statusCode":200,"response":{"geo_token":null}}"#),
            ])
            #expect(try await service.geoLookup() == nil)
        }
    }
}
