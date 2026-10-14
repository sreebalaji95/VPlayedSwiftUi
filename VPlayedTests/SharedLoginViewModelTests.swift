import Foundation
@preconcurrency import Shared
import Testing
@testable import VPlayed

/// Waits for state that the Kotlin controllers deliver on the main queue.
@MainActor
func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

extension StubbedBackendTests {
    /// The Login model on the shared controllers, against scripted backend answers.
    /// The flow rules themselves are tested in `../kmp` (`EmailLoginControllerTest`, `OtpControllerTest`).
    @MainActor
    @Suite
    struct SharedLoginViewModelTests {
        private static let codeSent = AuthStubURLProtocol.Answer.json(status: 200, body: #"{"statusCode":200,"message":"OTP sent"}"#)
        private static let signedIn = AuthStubURLProtocol.Answer.json(
            status: 200,
            body: #"{"statusCode":200,"response":{"_id":"u-1","email":"tester@example.com","first_name":"Test","access_token":"access-1"}}"#
        )
        private static let deviceLimit = AuthStubURLProtocol.Answer.json(status: 202, body: #"""
            {"statusCode":202,"message":"Signed in on 2 devices","response":{"device_limit":2,"get_devices":[
            {"username":"dev-1","access_token":"t-1","device_name":"Chrome on Linux","device_type":"web","browser_name":"Chrome","current_device":0},
            {"username":"dev-2","access_token":"t-2","device_name":"iPhone 15","device_type":"ios","current_device":1}]}}
            """#)

        private func makeModel(
            _ answers: [AuthStubURLProtocol.Answer],
            deviceSignOut: Bool = false,
            sessions: SessionManager = SessionManager(store: InMemorySecureStore())
        ) -> (SharedLoginViewModel, AccountStore) {
            AuthStubURLProtocol.reset(answers)
            let account = AccountStore(sessions: sessions, service: MockAuthService())
            // A 1-second resend wait and a short success step keep the tests fast.
            let config = AuthFlowConfig(deviceSignOutEnabled: deviceSignOut, resendSeconds: 1, successMillis: 50)
            return (SharedLoginViewModel(account: account, graph: StubbedBackend.graph(), config: config), account)
        }

        private func atCodeStep(_ answers: [AuthStubURLProtocol.Answer], sessions: SessionManager = SessionManager(store: InMemorySecureStore())) async throws -> (SharedLoginViewModel, AccountStore) {
            let (model, account) = makeModel([Self.codeSent] + answers, sessions: sessions)
            model.email = "tester@example.com"
            await model.continueWithEmail()
            try #require(await eventually { model.step == .code })
            return (model, account)
        }

        // MARK: Email step

        @Test func invalidEmailShowsAnErrorWithoutCallingTheAPI() async {
            let (model, _) = makeModel([])

            model.email = "not-an-email"
            await model.continueWithEmail()

            #expect(model.emailError != nil)
            #expect(model.step == .email)
            model.email = "tester@example.com"
            #expect(model.emailError == nil) // typing clears it
            #expect(AuthStubURLProtocol.captured.isEmpty)
        }

        @Test func emailIsCappedAt50Characters() {
            let (model, _) = makeModel([])
            model.email = String(repeating: "a", count: 60)
            #expect(model.email.count == SharedLoginViewModel.maxEmailLength)
        }

        @Test func aSentCodeOpensTheCodeStepWithTheCountdown() async throws {
            let (model, _) = try await atCodeStep([])

            #expect(model.sentTo == "tester@example.com")
            #expect(model.resendSeconds == 1)
            #expect(!model.isSending)
            #expect(AuthStubURLProtocol.captured.first?.request.url?.path == "/users/api/v1/auth/email-login")
        }

        @Test func aNewAccountAlsoGetsTheCodeStep() async throws {
            // Decision D2.
            let (model, _) = makeModel([.json(status: 203, body: #"{"statusCode":203}"#)])
            model.email = "new@example.com"
            await model.continueWithEmail()
            #expect(await eventually { model.step == .code })
        }

        @Test func theDeviceLimitShowsTheServerMessageWhileTheDeviceStepIsOff() async {
            // Decision D5: `AuthFeatures.deviceSignOut` is off.
            let (model, _) = makeModel([Self.deviceLimit])
            model.email = "tester@example.com"
            await model.continueWithEmail()

            #expect(await eventually { model.notice == "Signed in on 2 devices" })
            #expect(model.step == .email)
        }

        @Test func connectionFailuresShowTheAppsMessage() async {
            let (model, _) = makeModel([.failure(.cannotConnectToHost)])
            model.email = "tester@example.com"
            await model.continueWithEmail()

            #expect(await eventually { model.notice == SharedLoginViewModel.text(for: .errorNetwork) })
            #expect(!model.isSending)
        }

        @Test func guestLoginStartsAGuestSessionAndCloses() async {
            let (model, account) = makeModel([.json(status: 200, body: #"{"statusCode":200,"response":{"access_token":"guest-1","guest_user_id":"9001"}}"#)])

            await model.continueAsGuest()

            #expect(await eventually { model.isFinished })
            guard case .guest(let credentials) = account.state else {
                Issue.record("Expected a guest session")
                return
            }
            #expect(credentials.accessToken == "guest-1")
        }

        // MARK: Code step

        @Test func aCorrectCodeSignsInShowsTheSuccessStepThenFinishes() async throws {
            let sessions = SessionManager(store: InMemorySecureStore())
            let (model, account) = try await atCodeStep([Self.signedIn], sessions: sessions)

            model.code = "12a3456"
            #expect(model.code == "123456")
            #expect(model.canVerify)
            await model.verify()

            #expect(await eventually { model.step == .done })
            #expect(await eventually { model.isFinished })
            #expect(account.isSignedIn)
            #expect(sessions.session?.accessToken == "access-1")
            #expect(model.doneNotice == nil)
        }

        @Test func aWrongCodeShowsTheServerMessageAndClearsTheBoxes() async throws {
            let (model, account) = try await atCodeStep([.json(status: 400, body: #"{"error":true,"statusCode":400,"message":"Invalid OTP"}"#)])

            model.code = "000000"
            await model.verify()

            #expect(await eventually { model.notice == "Invalid OTP" })
            #expect(model.code.isEmpty)
            #expect(model.step == .code)
            #expect(account.state == .signedOut)
        }

        @Test func anUnregisteredAccountIsToldSo() async throws {
            let (model, _) = try await atCodeStep([.json(status: 203, body: #"{"statusCode":203}"#)])

            model.code = "123456"
            await model.verify()

            #expect(await eventually { model.notice == SharedLoginViewModel.text(for: .registrationRequired) })
        }

        @Test func resendIsAvailableAfterTheCountdown() async throws {
            let (model, _) = try await atCodeStep([Self.codeSent])

            #expect(await eventually { model.resendSeconds == 0 })
            await model.resend()

            #expect(await eventually { AuthStubURLProtocol.captured.count == 2 })
            #expect(await eventually { model.resendSeconds == 1 })
        }

        @Test func editingTheEmailGoesBack() async throws {
            let (model, _) = try await atCodeStep([])

            model.editEmail()

            #expect(model.step == .email)
            #expect(model.email == "tester@example.com")
            #expect(model.code.isEmpty)
        }

        // MARK: Device step (off in the app until the backend confirms it is safe)

        @Test func withTheDeviceStepOnDevicesCanBeSignedOutBeforeContinuing() async throws {
            let (model, _) = makeModel(
                [Self.deviceLimit, .json(status: 200, body: #"{"error":false}"#), Self.codeSent],
                deviceSignOut: true
            )
            model.email = "tester@example.com"
            await model.continueWithEmail()

            try #require(await eventually { model.step == .devices })
            #expect(model.devices.map(\.name) == ["Chrome on Linux", "iPhone 15"])
            #expect(model.devices.map(\.kind) == [.desktop, .phone])
            #expect(model.devices.map(\.isCurrent) == [false, true])
            #expect(model.maxDevices == 2)

            model.signOut(model.devices[0])
            #expect(await eventually { model.hasSignedOutDevice })
            #expect(model.devices.map(\.id) == ["dev-2"])
            let signOut = AuthStubURLProtocol.captured[1]
            #expect(signOut.request.url?.path == "/users/api/v1/auth/logout-device")

            // After the email step, Continue asks for a code again.
            model.continueAfterSignOut()
            #expect(await eventually { model.step == .code })
            #expect(AuthStubURLProtocol.captured.last?.request.url?.path == "/users/api/v1/auth/email-login")
        }

        // MARK: Messages

        @Test func everyMessageKeyHasText() {
            let keys = AuthMessageKey.entries
            for key in keys {
                #expect(!SharedLoginViewModel.text(for: key).isEmpty, "\(key)")
            }
            #expect(SharedLoginViewModel.text(AuthMessageServer(text: "From the server")) == "From the server")
        }
    }
}
