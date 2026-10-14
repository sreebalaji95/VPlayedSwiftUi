import Foundation
#if canImport(Shared)
@preconcurrency import Shared
#endif
import Testing
@testable import VPlayed

/// Scripted backend for `AuthServiceContractTests` (its own state, so suites running in parallel never share it).
final class AuthStubURLProtocol: URLProtocol {
    struct Captured {
        let request: URLRequest
        let body: Data
    }

    enum Answer {
        case json(status: Int, body: String)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [Answer] = []
    nonisolated(unsafe) private static var requests: [Captured] = []

    static func reset(_ scripted: [Answer]) { lock.withLock { answers = scripted; requests = [] } }

    static var captured: [Captured] { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let answer: Answer? = Self.lock.withLock {
            Self.requests.append(Captured(request: request, body: Self.body(of: request)))
            return Self.answers.isEmpty ? nil : Self.answers.removeFirst()
        }
        switch answer ?? .failure(.badServerResponse) {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .json(let status, let body):
            let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// URLSession moves POST bodies into a stream before a protocol sees them.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Suites that script `AuthStubURLProtocol`'s backend run one test at a time.
@Suite(.serialized)
enum StubbedBackendTests {}

#if canImport(Shared)
/// The shared layer wired to `AuthStubURLProtocol`, as the app wires it to the network.
enum StubbedBackend {
    static func graph(sessions: SessionManager = SessionManager(store: InMemorySecureStore())) -> SharedGraph {
        SharedLayer.makeGraph(
            environment: .development,
            appVersion: "9.9.9",
            transportKey: CryptoJSAES.authPassphrase,
            deviceInfo: IOSSharedDeviceInfo(deviceId: "test-device", deviceName: "iPhone17,3", languageCode: { "en" }),
            sessions: sessions,
            engineFactory: {
                HttpEngine_appleKt.createDarwinEngine { $0.protocolClasses = [AuthStubURLProtocol.self] }
            }
        )
    }
}
#endif

extension StubbedBackendTests {
    /// The backend contract of sign-in, run against every `AuthServicing` the app ships: the Kotlin
    /// shared layer (iOS, macOS) and the Swift fallback (visionOS). Both must follow decisions D1–D4.
    @MainActor
    @Suite
    struct AuthServiceContractTests {
        enum Implementation: String, CaseIterable, CustomTestStringConvertible {
            case swift
            #if canImport(Shared)
            case shared
            #endif

            var testDescription: String { rawValue }
        }

        /// A service whose requests reach `AuthStubURLProtocol`, and the session its requests read.
        private func make(_ implementation: Implementation, answers: [AuthStubURLProtocol.Answer]) -> (any AuthServicing, SessionStore) {
            AuthStubURLProtocol.reset(answers)
            switch implementation {
            case .swift:
                let store = SessionStore()
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [AuthStubURLProtocol.self]
                let client = APIClient(
                    environment: .development,
                    session: URLSession(configuration: configuration),
                    headers: RequestHeaders(session: store, deviceID: "test-device", appVersion: "9.9.9", languageCode: { "en" })
                )
                return (AuthService(client: client, deviceID: "test-device", deviceName: "iPhone17,3"), store)
            #if canImport(Shared)
            case .shared:
                // The app's wiring: one session manager behind both `SessionStore` and the graph.
                let sessions = SessionManager(store: InMemorySecureStore())
                return (SharedAuthService(graph: StubbedBackend.graph(sessions: sessions)), SessionStore(sessions: sessions))
            #endif
            }
        }

        /// The plain JSON inside the `{"data": …}` wrapper, decrypted with the build's transport key.
        private func decryptedData(_ captured: AuthStubURLProtocol.Captured) throws -> String {
            let wrapper = try #require(try JSONSerialization.jsonObject(with: captured.body) as? [String: String])
            #expect(Array(wrapper.keys) == ["data"])
            return try CryptoJSAES.decrypt(try #require(wrapper["data"]), passphrase: CryptoJSAES.authPassphrase)
        }

        private func json(_ data: String) throws -> NSDictionary {
            try #require(try JSONSerialization.jsonObject(with: Data(data.utf8)) as? NSDictionary)
        }

        // MARK: email-login

        @Test(arguments: Implementation.allCases)
        func sendingACodePostsTheEncryptedEmail(_ implementation: Implementation) async throws {
            let (service, _) = make(implementation, answers: [.json(status: 200, body: #"{"statusCode":200,"message":"OTP sent"}"#)])

            #expect(try await service.sendEmailCode(to: "tester@example.com") == .sent)

            let request = try #require(AuthStubURLProtocol.captured.first)
            #expect(request.request.url?.absoluteString == "https://api-devgs.vplayed.com/users/api/v1/auth/email-login")
            #expect(request.request.httpMethod == "POST")
            #expect(!String(decoding: request.body, as: UTF8.self).contains("tester@example.com"))
            #expect(try json(decryptedData(request)) == ["email": "tester@example.com"])
        }

        @Test(arguments: Implementation.allCases)
        func aNewAccountAlsoGetsACode(_ implementation: Implementation) async throws {
            // Decision D2: 203 goes to the code step (the UIKit app stopped with "no account").
            let (service, _) = make(implementation, answers: [.json(status: 203, body: #"{"statusCode":203,"message":"Welcome"}"#)])
            #expect(try await service.sendEmailCode(to: "new@example.com") == .sent)
        }

        @Test(arguments: Implementation.allCases)
        func theDeviceLimitIsReportedWhenAskingForACode(_ implementation: Implementation) async throws {
            // Decision D3.
            let (service, _) = make(implementation, answers: [.json(status: 202, body: #"{"error":true,"statusCode":202,"message":"Signed in on 2 devices"}"#)])
            #expect(try await service.sendEmailCode(to: "tester@example.com") == .deviceLimit(message: "Signed in on 2 devices"))
        }

        @Test(arguments: Implementation.allCases)
        func theEnvelopeStatusDecidesWithin2xx(_ implementation: Implementation) async throws {
            // Decision D1: HTTP 200 carrying `statusCode` 202 is the device limit.
            let (service, _) = make(implementation, answers: [.json(status: 200, body: #"{"statusCode":202,"message":"Limit"}"#)])
            #expect(try await service.sendEmailCode(to: "tester@example.com") == .deviceLimit(message: "Limit"))
        }

        @Test(arguments: Implementation.allCases)
        func refusalsShowTheServerMessage(_ implementation: Implementation) async throws {
            let (service, _) = make(implementation, answers: [.json(status: 422, body: #"{"error":true,"statusCode":422,"message":"Too many attempts"}"#)])

            await #expect {
                try await service.sendEmailCode(to: "tester@example.com")
            } throws: { error in
                (error as? APIError)?.userMessage == "Too many attempts"
            }
        }

        @Test(arguments: Implementation.allCases)
        func connectionFailuresAreNetworkErrors(_ implementation: Implementation) async throws {
            let (service, _) = make(implementation, answers: [.failure(.cannotConnectToHost)])

            await #expect {
                try await service.sendEmailCode(to: "tester@example.com")
            } throws: { error in
                if case .network = error as? APIError { true } else { false }
            }
        }

        // MARK: verifyEmailOtp

        @Test(arguments: Implementation.allCases)
        func aCorrectCodeSignsIn(_ implementation: Implementation) async throws {
            let body = #"""
            {"statusCode":200,"response":{"_id":"u-1","unique_user_id":"4211","email":"tester@example.com",
            "first_name":"Test","access_token":"access-1","refresh_token":"refresh-1","google_auth_id":"g"}}
            """#
            let (service, _) = make(implementation, answers: [.json(status: 200, body: body)])

            let outcome = try await service.verifyEmailCode("123456", email: "tester@example.com")

            let expected = AuthCredentials(accessToken: "access-1", refreshToken: "refresh-1", userID: "u-1", uniqueUserID: 4211, email: "tester@example.com", phone: nil, firstName: "Test", isGuest: false)
            #expect(outcome == .signedIn(expected))
            let request = try #require(AuthStubURLProtocol.captured.first)
            #expect(request.request.url?.path == "/users/api/v1/auth/verifyEmailOtp")
            #expect(try json(decryptedData(request)) == ["email": "tester@example.com", "otp": "123456", "deviceDetail": "iPhone17,3"])
        }

        @Test(arguments: Implementation.allCases)
        func anEmailOnlyAccountSignsIn(_ implementation: Implementation) async throws {
            // Decision D4: no "linked sign-in" rule any more (no phone, Apple, Facebook or Google id here).
            let (service, _) = make(implementation, answers: [.json(status: 200, body: #"{"statusCode":200,"response":{"access_token":"access-1","email":"tester@example.com"}}"#)])

            guard case .signedIn(let credentials) = try await service.verifyEmailCode("123456", email: "tester@example.com") else {
                Issue.record("Expected a session")
                return
            }
            #expect(credentials.accessToken == "access-1")
        }

        @Test(arguments: Implementation.allCases)
        func aNewAccountWithASessionSignsIn(_ implementation: Implementation) async throws {
            let (service, _) = make(implementation, answers: [.json(status: 203, body: #"{"statusCode":203,"response":{"access_token":"access-1"}}"#)])

            guard case .signedIn = try await service.verifyEmailCode("123456", email: "new@example.com") else {
                Issue.record("Expected a session")
                return
            }
        }

        @Test(arguments: Implementation.allCases)
        func aNewAccountWithoutASessionMustRegister(_ implementation: Implementation) async throws {
            let (service, _) = make(implementation, answers: [.json(status: 203, body: #"{"statusCode":203,"message":"Please register"}"#)])
            #expect(try await service.verifyEmailCode("123456", email: "new@example.com") == .newAccount)
        }

        @Test(arguments: Implementation.allCases)
        func theDeviceLimitIsReportedWhenVerifying(_ implementation: Implementation) async throws {
            let (service, _) = make(implementation, answers: [.json(status: 202, body: #"{"statusCode":202,"message":"Signed in on 2 devices"}"#)])
            #expect(try await service.verifyEmailCode("123456", email: "tester@example.com") == .deviceLimit(message: "Signed in on 2 devices"))
        }

        @Test(arguments: Implementation.allCases)
        func aWrongCodeShowsTheServerMessage(_ implementation: Implementation) async throws {
            let (service, _) = make(implementation, answers: [.json(status: 400, body: #"{"error":true,"statusCode":400,"message":"Invalid OTP"}"#)])

            await #expect {
                try await service.verifyEmailCode("000000", email: "tester@example.com")
            } throws: { error in
                (error as? APIError)?.userMessage == "Invalid OTP"
            }
        }

        // MARK: Guest and logout

        @Test(arguments: Implementation.allCases)
        func guestLoginSendsTheDeviceIDAndStartsAGuestSession(_ implementation: Implementation) async throws {
            let body = #"{"statusCode":200,"response":{"access_token":"guest-1","_id":"g1","guest_user_id":"9001","unique_user_id":5}}"#
            let (service, _) = make(implementation, answers: [.json(status: 200, body: body)])

            let credentials = try await service.guestLogin()

            #expect(credentials.isGuest)
            #expect(credentials.accessToken == "guest-1")
            let request = try #require(AuthStubURLProtocol.captured.first)
            #expect(request.request.url?.path == "/users/api/v1/auth/generate")
            #expect(try JSONSerialization.jsonObject(with: request.body) as? NSDictionary == ["uuid": "test-device"])
        }

        @Test(arguments: Implementation.allCases)
        func logoutSendsTheSessionToken(_ implementation: Implementation) async throws {
            let (service, store) = make(implementation, answers: [.json(status: 200, body: #"{"statusCode":200}"#)])
            await store.signIn(AuthCredentials(accessToken: "access-1", refreshToken: nil, userID: nil, uniqueUserID: nil, email: nil, phone: nil, firstName: nil, isGuest: false))

            try await service.logout()

            let request = try #require(AuthStubURLProtocol.captured.first)
            #expect(request.request.url?.path == "/users/api/v1/auth/logout")
            #expect(request.request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        }

        @Test(arguments: Implementation.allCases)
        func logoutWithAnExpiredTokenIsUnauthorized(_ implementation: Implementation) async throws {
            let (service, _) = make(implementation, answers: [.json(status: 401, body: "")])
            await #expect(throws: APIError.unauthorized) { try await service.logout() }
        }
    }
}
