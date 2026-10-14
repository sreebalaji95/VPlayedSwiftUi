import Foundation
@preconcurrency import Shared
import Testing
@testable import VPlayed

/// How Swift meets the Kotlin shared layer (KMP-604): suspend calls, watchers, and the Darwin
/// engine's transport failures reaching Swift as typed results.
extension RoutedBackendTests {
    @MainActor
    @Suite
    struct SharedInteropTests {
        private static let common = RoutedBackend.route("mediaview/api/v1/common")
        private static let commonBody = #"{"statusCode":200,"response":{"content_library":1}}"#

        private func load(_ answer: RouteStubURLProtocol.Answer) async throws -> any DataResult {
            RouteStubURLProtocol.reset([Self.common: answer])
            return try await RoutedBackend.graph().commonSettingsRepository.load()
        }

        @Test func aDarwinTimeoutIsATimeoutNotAnUnknownError() async throws {
            let result = try await load(.failure(.timedOut))

            let failure = try #require(result as? DataResultFailure)
            #expect(failure.error is AppErrorTimeout)
            // The screens' message for it (VPlayed shows its own timeout text).
            #expect(APIError(failure.error) == .network(code: URLError.timedOut.rawValue))
        }

        @Test func beingOfflineIsANetworkFailure() async throws {
            for code in [URLError.Code.notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost] {
                let result = try await load(.failure(code))

                let failure = try #require(result as? DataResultFailure, "\(code)")
                #expect(failure.error is AppErrorNetwork, "\(code)")
            }
        }

        @Test func aSuspendCallFromACancelledTaskStillCompletesWithATypedResult() async throws {
            // Swift cancellation does not reach Kotlin coroutines: the call finishes and returns normally.
            RouteStubURLProtocol.reset([Self.common: .json(status: 200, body: Self.commonBody)])
            let graph = RoutedBackend.graph()
            let task = Task { try await graph.commonSettingsRepository.load() }
            task.cancel()

            let result = try await task.value

            #expect(result is DataResultSuccess<Shared.CommonSettings>)
        }

        @Test func watchersDeliverOnTheMainThreadStartingWithTheCurrentValueAndStopWhenClosed() async throws {
            let sessions = SessionManager(store: InMemorySecureStore())
            try await sessions.awaitLoaded()
            var received: [String] = []
            var onMain = true

            let watch = sessions.watchStatus { status in
                onMain = onMain && Thread.isMainThread
                received.append(String(describing: type(of: status)))
            }
            for _ in 0..<100 where received.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
            #expect(received.count == 1, "the current value first")

            try await sessions.signIn(session: AuthSession(AuthCredentials(accessToken: "a", refreshToken: nil, userID: nil, uniqueUserID: nil, email: nil, phone: nil, firstName: nil, isGuest: false)))
            for _ in 0..<100 where received.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
            #expect(received.count == 2)

            watch.close()
            try await sessions.signOut(reason: .user)
            try await Task.sleep(for: .milliseconds(200))

            #expect(received.count == 2, "nothing after close")
            #expect(onMain)
            watch.close() // A second close is harmless.
        }

        @Test func kotlinEnumsAndSealedTypesKeepTheirMeaningInSwift() {
            #expect(SessionStatusSignedOut(reason: .expired) == SessionStatusSignedOut(reason: .expired))
            #expect(SessionStatusSignedOut(reason: .expired) != SessionStatusSignedOut(reason: .user))
            #expect(SecureKey.session.name == "SESSION")
            #expect(GeoRefreshOutcome.transientFailure.name == "TRANSIENT_FAILURE")
        }
    }
}
