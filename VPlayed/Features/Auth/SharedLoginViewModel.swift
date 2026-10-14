import Foundation
import Observation
// Kotlin classes are not Sendable; they are only used on the main thread here.
@preconcurrency import Shared

/// The Login screen's model: the Kotlin shared controllers (`EmailLoginController`,
/// `OtpController`, also behind AndroidJP's Login and OTP screens) run the flow: validation, one
/// request at a time, the resend countdown, the device-limit step and the success step. This class
/// mirrors their state for SwiftUI, turns messages into this app's strings and stores the session
/// in `AccountStore`.
@Observable
final class SharedLoginViewModel {
    /// Digits in a login code (the shared rule, `AuthFlowConfig.CODE_LENGTH`).
    static let codeLength = Int(AuthFlowConfig.companion.CODE_LENGTH)

    /// The UIKit app's cap on the email field.
    static let maxEmailLength = 50

    private(set) var step: LoginStep = .email
    private(set) var emailError: String?
    private(set) var sentTo = ""
    private(set) var resendSeconds = 0
    private(set) var isVerifying = false
    private(set) var isJoiningAsGuest = false
    private(set) var isFinished = false
    private(set) var notice: String?
    private(set) var doneNotice: String?
    private(set) var devices: [LoginDevice] = []
    private(set) var maxDevices: Int?
    private(set) var isSigningOut = false
    private(set) var hasSignedOutDevice = false

    private var emailText = ""
    private var codeText = ""
    private var isSubmitting = false
    private var isResending = false
    /// The email step's message; the code and device steps show the OTP controller's error instead.
    private var emailNotice: String?
    private var otpError: String?

    var email: String {
        get { emailText }
        set {
            emailController.onEmailChange(value: String(newValue.prefix(Self.maxEmailLength)))
            apply(emailController.currentState)
        }
    }

    var code: String {
        get { codeText }
        set {
            guard let otp = otpController else { return }
            otp.onCodeChange(value: newValue)
            apply(otp.currentState)
        }
    }

    var isSending: Bool { isSubmitting || isResending }
    var canVerify: Bool { codeText.count == Self.codeLength && !isVerifying }

    @ObservationIgnored private let account: AccountStore
    @ObservationIgnored private let graph: SharedGraph
    @ObservationIgnored private let config: AuthFlowConfig
    @ObservationIgnored private let emailController: EmailLoginController
    @ObservationIgnored private var otpController: OtpController?
    /// Kotlin devices behind `devices`, for the sign-out calls.
    @ObservationIgnored private var kotlinDevices: [String: SignedInDevice] = [:]
    /// Stores the session; `Authenticated` waits for it so the app is signed in before the screen closes.
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private let emailWatchers = KotlinSubscriptions()
    @ObservationIgnored private let otpWatchers = KotlinSubscriptions()

    init(
        account: AccountStore,
        graph: SharedGraph = SharedLayer.graph,
        config: AuthFlowConfig = AuthFlowConfig(deviceSignOutEnabled: AuthFeatures.deviceSignOut, resendSeconds: AuthFlowConfig.companion.RESEND_SECONDS, successMillis: AuthFlowConfig.companion.SUCCESS_MILLIS)
    ) {
        self.account = account
        self.graph = graph
        self.config = config
        let controller = graph.emailLoginController(config: config)
        emailController = controller
        emailWatchers.add(controller.close)
        emailWatchers.add(controller.watchState { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }.close)
        emailWatchers.add(controller.watchEffects { [weak self] effect in
            MainActor.assumeIsolated { self?.handle(effect) }
        }.close)
    }

    // MARK: Email step

    func continueWithEmail() async {
        emailNotice = nil
        emailController.onSubmit()
        apply(emailController.currentState)
    }

    func continueAsGuest() async {
        emailNotice = nil
        emailController.joinAsGuest()
        apply(emailController.currentState)
    }

    // MARK: Code step

    func verify() async {
        otpController?.onVerify()
        otpController.map { apply($0.currentState) }
    }

    func resend() async {
        otpController?.onResend()
        otpController.map { apply($0.currentState) }
    }

    func editEmail() {
        if let otp = otpController, otp.currentState.step == .devices {
            // From the device step reached after a code, Back returns to the code step.
            otp.onBack()
            apply(otp.currentState)
            if step != .email { return }
        }
        endOtp()
        step = .email
    }

    func stopTimers() {
        endOtp()
    }

    // MARK: Device step

    func signOut(_ device: LoginDevice) {
        guard let otp = otpController, let kotlinDevice = kotlinDevices[device.id] else { return }
        otp.onSignOutDevice(device: kotlinDevice)
        apply(otp.currentState)
    }

    func signOutAllDevices() {
        guard let otp = otpController else { return }
        otp.onSignOutAllDevices()
        apply(otp.currentState)
    }

    func continueAfterSignOut() {
        guard let otp = otpController else { return }
        otp.onContinueAfterSignOut()
        apply(otp.currentState)
    }

    // MARK: Shared state and effects

    private func apply(_ state: EmailLoginState) {
        emailText = state.email
        emailError = state.emailError.map { _ in
            // The field is capped at 50 characters, so every error is about the address itself.
            String(localized: "Please enter a valid email address", bundle: .localized)
        }
        isSubmitting = state.isSubmitting
        isJoiningAsGuest = state.isJoiningAsGuest
        if step == .email { notice = emailNotice }
    }

    private func apply(_ state: OtpState) {
        codeText = state.code
        resendSeconds = Int(state.resendSecondsLeft)
        isVerifying = state.isVerifying
        isResending = state.isResending
        otpError = state.error.map(Self.text)
        doneNotice = state.notice.map(Self.text)
        maxDevices = state.maxDevices.map { Int(truncating: $0) }
        isSigningOut = state.isSigningOut
        hasSignedOutDevice = state.hasSignedOutDevice
        kotlinDevices = Dictionary(state.devices.map { (Self.id(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        devices = state.devices.map(Self.loginDevice)
        switch state.step {
        case .devices: step = .devices
        case .success: step = .done
        default: step = .code
        }
        notice = otpError
    }

    private func handle(_ effect: EmailLoginEffect) {
        switch effect {
        case let sent as EmailLoginEffectCodeSent:
            startOtp(email: sent.email, deviceLimit: nil)
        case let devicesEffect as EmailLoginEffectShowDevices:
            startOtp(email: devicesEffect.email, deviceLimit: devicesEffect.limit)
        case let message as EmailLoginEffectShowMessage:
            emailNotice = Self.text(message.message)
            if step == .email { notice = emailNotice }
        case let guest as EmailLoginEffectGuestSignedIn:
            let credentials = AuthCredentials(guest.session)
            Task { [account] in
                await account.complete(with: credentials)
                self.isFinished = true
            }
        default:
            break
        }
    }

    private func handle(_ effect: OtpEffect) {
        switch effect {
        case let signedIn as OtpEffectSignedIn:
            let credentials = AuthCredentials(signedIn.session)
            sessionTask = Task { [account] in await account.complete(with: credentials) }
        case is OtpEffectAuthenticated:
            Task { [sessionTask] in
                await sessionTask?.value
                self.isFinished = true
            }
        case is OtpEffectNavigateBack:
            endOtp()
            step = .email
        default:
            break
        }
    }

    private func startOtp(email: String, deviceLimit: DeviceLimit?) {
        endOtp()
        sentTo = email
        let controller = graph.otpController(email: email, initialDeviceLimit: deviceLimit, config: config)
        otpController = controller
        otpWatchers.add(controller.close)
        otpWatchers.add(controller.watchState { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }.close)
        otpWatchers.add(controller.watchEffects { [weak self] effect in
            MainActor.assumeIsolated { self?.handle(effect) }
        }.close)
        apply(controller.currentState)
    }

    private func endOtp() {
        otpWatchers.closeAll()
        otpController = nil
        codeText = ""
        resendSeconds = 0
        isVerifying = false
        isResending = false
        otpError = nil
        devices = []
        kotlinDevices = [:]
        notice = nil
        emailNotice = nil
    }

    // MARK: Mapping

    private static func id(of device: SignedInDevice) -> String {
        device.signOutKey.username
    }

    private static func loginDevice(_ device: SignedInDevice) -> LoginDevice {
        let kind: LoginDevice.Kind = switch device.kind {
        case .desktop: .desktop
        case .phone: .phone
        case .tv: .tv
        default: .other
        }
        return LoginDevice(id: id(of: device), name: device.name, kind: kind, detail: device.detail, isCurrent: device.isCurrent)
    }

    /// This app's text for a shared sign-in message.
    static func text(_ message: any AuthMessage) -> String {
        if let server = message as? AuthMessageServer { return server.text }
        guard let key = (message as? AuthMessageLocalized)?.key else {
            return String(localized: "Something went wrong while loading. Please try again.", bundle: .localized)
        }
        return text(for: key)
    }

    static func text(for key: AuthMessageKey) -> String {
        switch key {
        case .deviceLimit:
            String(localized: "You're signed in on the maximum number of devices. Sign out on another device, then try again.", bundle: .localized)
        case .loginFailed, .guestLoginFailed:
            String(localized: "We couldn't sign you in. Please try again.", bundle: .localized)
        case .otpInvalid:
            String(localized: "Incorrect code. Try again.", bundle: .localized)
        case .registrationRequired:
            String(localized: "This email isn't registered yet. Create your account on the \(Brand.name) website, then sign in.", bundle: .localized)
        case .deviceSignOutFailed:
            String(localized: "We couldn't sign that device out. Please try again.", bundle: .localized)
        case .profileSetupPending:
            String(localized: "Welcome! Setting up your profile is coming soon.", bundle: .localized)
        case .multiProfilePending:
            String(localized: "Choosing a profile is coming soon; your default profile is used.", bundle: .localized)
        case .errorNetwork:
            String(localized: "We couldn't reach \(Brand.name). Please try again.", bundle: .localized)
        case .errorTimeout:
            String(localized: "The server took too long to respond. Please try again.", bundle: .localized)
        case .errorUnauthorized:
            String(localized: "Your session has expired. Please sign in again.", bundle: .localized)
        default:
            String(localized: "Something went wrong while loading. Please try again.", bundle: .localized)
        }
    }
}

/// Closes Kotlin subscriptions and controllers: on demand, and at the latest when its owner goes away.
nonisolated final class KotlinSubscriptions: @unchecked Sendable {
    private let lock = NSLock()
    private var closers: [() -> Void] = []

    func add(_ close: @escaping () -> Void) {
        lock.withLock { closers.append(close) }
    }

    func closeAll() {
        let pending = lock.withLock { () -> [() -> Void] in
            defer { closers = [] }
            return closers
        }
        pending.forEach { $0() }
    }

    deinit { closeAll() }
}
