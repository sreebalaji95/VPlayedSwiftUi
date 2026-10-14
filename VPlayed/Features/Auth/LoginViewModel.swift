import Foundation
import Observation

/// The Swift Login model, used on visionOS (no Kotlin/Native target): the UIKit app's passwordless
/// email sign-in (email → 6-digit code) and guest login, with its validation, resend timer and
/// outcome handling, on `AuthServicing`. iOS and macOS use `SharedLoginViewModel`, which runs the
/// same flow on the Kotlin shared controllers. Removed if visionOS gets the shared layer (Phase 7).
@Observable
final class LoginViewModel: LoginScreenModel {
    typealias Step = LoginStep

    /// UIKit's limits: an email field of at most 50 characters, a 60-second resend wait.
    static let maxEmailLength = 50
    static let codeLength = 6
    static let resendInterval = 60

    private(set) var step: Step = .email {
        didSet {
            // "You're all set" moves on by itself after 3 seconds, as in the prototype.
            if step == .done { finishAfterSuccessStep() }
        }
    }
    var email = "" {
        didSet {
            if email.count > Self.maxEmailLength { email = String(email.prefix(Self.maxEmailLength)) }
            if email != oldValue { emailError = nil }
        }
    }
    private(set) var emailError: String?
    /// Digits only, at most six.
    var code = "" {
        didSet {
            let digits = String(code.filter(\.isASCIIDigit).prefix(Self.codeLength))
            if digits != code { code = digits }
        }
    }
    /// The address the code was sent to.
    private(set) var sentTo = ""
    /// Seconds until "Resend" is available again.
    private(set) var resendSeconds = 0
    private(set) var isSending = false
    private(set) var isVerifying = false
    private(set) var isJoiningAsGuest = false
    /// Set when a session has started (guest at once, sign-in after the success step), so the screen can close.
    private(set) var isFinished = false
    /// An error to show above the form (server messages, connection problems).
    var notice: String?

    var canVerify: Bool { code.count == Self.codeLength && !isVerifying }

    @ObservationIgnored private let service: any AuthServicing
    @ObservationIgnored private let account: AccountStore
    @ObservationIgnored private var resendTask: Task<Void, Never>?
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    /// How long "You're all set" stays.
    static let successDuration = Duration.seconds(3)

    init(account: AccountStore, service: any AuthServicing = AuthServices.live()) {
        self.account = account
        self.service = service
    }

    /// The UIKit app's `isValidEmail` pattern.
    static func isValidEmail(_ email: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}").evaluate(with: email)
    }

    // MARK: Email step

    func continueWithEmail() async {
        guard !isSending else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(address) else {
            emailError = String(localized: "Please enter a valid email address", bundle: .localized)
            return
        }
        email = address
        notice = nil
        isSending = true
        defer { isSending = false }
        do {
            switch try await service.sendEmailCode(to: address) {
            case .sent:
                sentTo = address
                code = ""
                step = .code
                startResendTimer()
            case .deviceLimit(let message):
                notice = deviceLimitNotice(message)
            }
        } catch {
            show(error)
        }
    }

    func continueAsGuest() async {
        guard !isJoiningAsGuest else { return }
        notice = nil
        isJoiningAsGuest = true
        defer { isJoiningAsGuest = false }
        do {
            await account.complete(with: try await service.guestLogin())
            isFinished = true
        } catch {
            show(error)
        }
    }

    // MARK: Code step

    func verify() async {
        guard canVerify else { return }
        notice = nil
        isVerifying = true
        defer { isVerifying = false }
        do {
            switch try await service.verifyEmailCode(code, email: sentTo) {
            case .signedIn(let credentials):
                resendTask?.cancel()
                await account.complete(with: credentials)
                step = .done
            case .deviceLimit(let message):
                code = ""
                notice = deviceLimitNotice(message)
            case .newAccount:
                code = ""
                notice = String(localized: "This email isn't registered yet. Create your account on the \(Brand.name) website, then sign in.", bundle: .localized)
            }
        } catch {
            code = ""
            show(error)
        }
    }

    func resend() async {
        guard resendSeconds == 0, !isSending, !sentTo.isEmpty else { return }
        notice = nil
        isSending = true
        defer { isSending = false }
        do {
            switch try await service.sendEmailCode(to: sentTo) {
            case .sent:
                code = ""
                startResendTimer()
            case .deviceLimit(let message):
                notice = deviceLimitNotice(message)
            }
        } catch {
            show(error)
        }
    }

    /// "Back" and "Change": return to the email step to fix the address.
    func editEmail() {
        stopTimers()
        resendSeconds = 0
        code = ""
        notice = nil
        step = .email
    }

    func stopTimers() {
        resendTask?.cancel()
        resendTask = nil
    }

    private func finishAfterSuccessStep() {
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: Self.successDuration)
            guard let self, !Task.isCancelled else { return }
            isFinished = true
        }
    }

    private func startResendTimer() {
        resendTask?.cancel()
        resendSeconds = Self.resendInterval
        resendTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                resendSeconds = max(0, resendSeconds - 1)
                if resendSeconds == 0 { return }
            }
        }
    }

    /// The server's explanation, else ours. Signing other devices out is not offered on iOS yet (D5).
    private func deviceLimitNotice(_ message: String?) -> String {
        message.flatMap { $0.isEmpty ? nil : $0 }
            ?? String(localized: "You're signed in on the maximum number of devices. Sign out on another device, then try again.", bundle: .localized)
    }

    private func show(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        notice = (error as? APIError)?.userMessage ?? APIError.network(code: 0).userMessage
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
