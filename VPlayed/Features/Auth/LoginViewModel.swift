import Foundation
import Observation

/// Drives the Login screen: the UIKit app's passwordless email sign-in (email → 6-digit code)
/// and guest login, with its validation, resend timer and outcome handling.
@Observable
final class LoginViewModel {
    enum Step: Equatable {
        case email
        case code
        /// Signed in; the screen shows "You're all set" and closes itself.
        case done
    }

    /// UIKit's limits: an email field of at most 50 characters, a 60-second resend wait.
    static let maxEmailLength = 50
    static let codeLength = 6
    static let resendInterval = 60

    private(set) var step: Step = .email
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
    /// Set when a guest session has started, so the screen can close.
    private(set) var isFinished = false
    /// An error to show above the form (server messages, connection problems).
    var notice: String?

    var canVerify: Bool { code.count == Self.codeLength && !isVerifying }

    @ObservationIgnored private let service: any AuthServicing
    @ObservationIgnored private let account: AccountStore
    @ObservationIgnored private var resendTask: Task<Void, Never>?

    init(account: AccountStore, service: any AuthServicing = AuthService()) {
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
            case .newAccount:
                notice = String(localized: "There's no \(Brand.name) account for this email yet.", bundle: .localized)
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
                notice = message.flatMap { $0.isEmpty ? nil : $0 }
                    ?? String(localized: "You're signed in on the maximum number of devices. Sign out on another device, then try again.", bundle: .localized)
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
            case .newAccount:
                notice = String(localized: "There's no \(Brand.name) account for this email yet.", bundle: .localized)
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

    private func show(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        notice = (error as? APIError)?.userMessage ?? APIError.network(code: 0).userMessage
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
