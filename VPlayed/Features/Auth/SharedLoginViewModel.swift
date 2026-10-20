import Foundation
import Observation
// Kotlin classes are not Sendable; they are only used on the main thread here.
@preconcurrency import Shared

/// The Login screen's model: the Kotlin shared controllers (`EmailLoginController`,
/// `PhoneLoginController`, `SocialLoginController`, `OtpController`, also behind AndroidJP's Login
/// and OTP screens) run the flow: validation, one request at a time, the resend countdown, the
/// device-limit step and the success step. This class mirrors their state for SwiftUI, runs the
/// platform parts (Firebase SMS, the Google and Apple sheets), turns messages into this app's
/// strings and stores the session in `AccountStore`.
///
/// Step 1 asks for a mobile number instead of an email when the common settings choose phone
/// verification (`otp_verfied`) and this build has Firebase settings. A new account then fills in
/// the sign-up form (`RegistrationController`) before its session is stored; every sign-in uses the
/// account's first profile (the shared `profileChooser`; no profile picker yet).
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
    /// A neutral line on the code step ("code sent").
    private(set) var codeInfo: String?

    // Sign-up form (step `.register`).
    private(set) var registrationKind: RegistrationKind?
    private(set) var registrationNameError: String?
    private(set) var registrationEmailError: String?
    private(set) var registrationCountry: CountryDialCode = CountryDialCodes.shared.DEFAULT
    private(set) var registrationNumberError: String?
    private(set) var isReferralVisible = false
    private(set) var isRegistering = false
    /// The name the account was set up with, for "You're all set, …".
    private(set) var registeredName: String?

    /// Step 1 asks for a mobile number (see the class comment).
    let usesPhone: Bool
    private(set) var phoneError: String?
    private(set) var country: CountryDialCode
    /// The countries the picker offers (sign-in prototype).
    let countries: [CountryDialCode] = CountryDialCodes.shared.all
    /// Google sign-in needs this build's OAuth client ID.
    let isGoogleAvailable: Bool
    /// The provider whose sheet or `auth/login` call is running.
    private(set) var socialInFlight: SocialProvider?

    private var emailText = ""
    private var phoneText = ""
    private var isPhoneSubmitting = false
    private var codeText = ""
    private var isSubmitting = false
    private var isResending = false
    /// The email step's message; the code and device steps show the OTP controller's error instead.
    private var emailNotice: String?
    private var otpError: String?
    private var registrationNameText = ""
    private var registrationEmailText = ""
    private var registrationNumberText = ""
    private var referralText = ""

    var email: String {
        get { emailText }
        set {
            emailController.onEmailChange(value: String(newValue.prefix(Self.maxEmailLength)))
            apply(emailController.currentState)
        }
    }

    /// The national number as typed, grouped `98765 43210`.
    var phoneNumber: String {
        get { phoneText }
        set {
            guard let phone = phoneController else { return }
            phone.onNumberChange(value: newValue)
            apply(phone.currentState)
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

    var registrationName: String {
        get { registrationNameText }
        set {
            guard let form = registrationController else { return }
            form.onNameChange(value: newValue)
            apply(form.currentState)
        }
    }

    var registrationEmail: String {
        get { registrationEmailText }
        set {
            guard let form = registrationController else { return }
            form.onEmailChange(value: newValue)
            apply(form.currentState)
        }
    }

    /// The mobile number, grouped `98765 43210`; typed by an email account, read-only for a phone account.
    var registrationNumber: String {
        get { registrationNumberText }
        set {
            guard let form = registrationController else { return }
            form.onNumberChange(value: newValue)
            apply(form.currentState)
        }
    }

    var referralCode: String {
        get { referralText }
        set {
            guard let form = registrationController else { return }
            form.onReferralChange(value: newValue)
            apply(form.currentState)
        }
    }

    var isSending: Bool { isSubmitting || isPhoneSubmitting || isResending }
    /// A social sign-in, code request or guest session is running: the other step-1 actions wait.
    var isBusy: Bool { isSending || isJoiningAsGuest || socialInFlight != nil }
    var canVerify: Bool { codeText.count == Self.codeLength && !isVerifying }

    @ObservationIgnored private let account: AccountStore
    @ObservationIgnored private let graph: SharedGraph
    @ObservationIgnored private let config: AuthFlowConfig
    @ObservationIgnored private let emailController: EmailLoginController
    @ObservationIgnored private let phoneController: PhoneLoginController?
    @ObservationIgnored private let socialController: SocialLoginController
    @ObservationIgnored private let phoneSender: any PhoneOtpSender
    @ObservationIgnored private let social: any SocialSigningIn
    @ObservationIgnored private var otpController: OtpController?
    @ObservationIgnored private var registrationController: RegistrationController?
    /// Kotlin devices behind `devices`, for the sign-out calls.
    @ObservationIgnored private var kotlinDevices: [String: SignedInDevice] = [:]
    /// Stores the session; `Authenticated` waits for it so the app is signed in before the screen closes.
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private let emailWatchers = KotlinSubscriptions()
    @ObservationIgnored private let stepWatchers = KotlinSubscriptions()
    @ObservationIgnored private let otpWatchers = KotlinSubscriptions()
    @ObservationIgnored private let registrationWatchers = KotlinSubscriptions()

    init(
        account: AccountStore,
        graph: SharedGraph = SharedLayer.graph,
        config: AuthFlowConfig = AuthFlowConfig(deviceSignOutEnabled: AuthFeatures.deviceSignOut, resendSeconds: AuthFlowConfig.companion.RESEND_SECONDS, successMillis: AuthFlowConfig.companion.SUCCESS_MILLIS),
        verificationMethod: CommonSettings.VerificationMethod? = nil,
        phoneSender: any PhoneOtpSender = FirebasePhoneOtpSender.shared,
        social: any SocialSigningIn = LiveSocialSignIn(),
        regionCode: String? = Locale.current.region?.identifier,
        initialNotice: String? = nil
    ) {
        self.account = account
        self.graph = graph
        self.config = config
        self.phoneSender = phoneSender
        self.social = social
        isGoogleAvailable = social.isGoogleAvailable
        // Without Firebase there is no way to text a code, so email sign-in stays available.
        usesPhone = (verificationMethod == .phone || verificationMethod == .mobile) && FirebaseBootstrap.isPhoneSignInReady
        emailNotice = initialNotice
        notice = initialNotice
        let phone = usesPhone ? graph.phoneLoginController(config: config, regionCode: regionCode) : nil
        phoneController = phone
        country = phone?.currentState.country ?? CountryDialCodes.shared.DEFAULT
        socialController = graph.socialLoginController(config: config)
        let controller = graph.emailLoginController(config: config)
        emailController = controller
        emailWatchers.add(controller.close)
        emailWatchers.add(controller.watchState { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }.close)
        emailWatchers.add(controller.watchEffects { [weak self] effect in
            MainActor.assumeIsolated { self?.handle(effect) }
        }.close)
        if let phone {
            stepWatchers.add(phone.close)
            stepWatchers.add(phone.watchState { [weak self] state in
                MainActor.assumeIsolated { self?.apply(state) }
            }.close)
            stepWatchers.add(phone.watchEffects { [weak self] effect in
                MainActor.assumeIsolated { self?.handle(effect) }
            }.close)
        }
        stepWatchers.add(socialController.close)
        stepWatchers.add(socialController.watchState { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }.close)
        stepWatchers.add(socialController.watchEffects { [weak self] effect in
            MainActor.assumeIsolated { self?.handle(effect) }
        }.close)
    }

    // MARK: Email step

    func continueWithEmail() async {
        emailNotice = nil
        emailController.onSubmit()
        apply(emailController.currentState)
    }

    func continueWithPhone() async {
        guard let phone = phoneController else { return }
        emailNotice = nil
        phone.onSubmit()
        apply(phone.currentState)
    }

    func selectCountry(_ country: CountryDialCode) {
        guard let phone = phoneController else { return }
        phone.onCountryChange(country: country)
        apply(phone.currentState)
    }

    func phoneFieldLostFocus() {
        guard let phone = phoneController else { return }
        phone.onNumberFocusLost()
        apply(phone.currentState)
    }

    func continueAsGuest() async {
        // The automatic guest session (common settings) may already be running.
        if case .guest = account.state {
            isFinished = true
            return
        }
        emailNotice = nil
        emailController.joinAsGuest()
        apply(emailController.currentState)
    }

    func signInWithGoogle() async {
        await signIn(with: .google) { await $0.google() }
    }

    func signInWithApple() async {
        await signIn(with: .apple) { await $0.apple() }
    }

    private func signIn(with provider: SocialProvider, using run: (any SocialSigningIn) async -> SocialSignInOutcome) async {
        guard socialController.canStart, !isSending, !isJoiningAsGuest else { return }
        emailNotice = nil
        notice = nil
        socialController.onProviderStarted(provider: provider)
        apply(socialController.currentState)
        switch await run(social) {
        case let .credential(credential):
            socialController.onCredential(credential: credential)
        case .cancelled:
            socialController.onProviderFinished(provider: provider, cancelled: true)
        case .failed:
            socialController.onProviderFinished(provider: provider, cancelled: false)
        }
        apply(socialController.currentState)
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
        endRegistration()
    }

    // MARK: Sign-up form

    func submitRegistration() {
        guard let form = registrationController else { return }
        form.onSubmit()
        apply(form.currentState)
    }

    func showReferral() {
        guard let form = registrationController else { return }
        form.onShowReferral()
        apply(form.currentState)
    }

    func selectRegistrationCountry(_ country: CountryDialCode) {
        guard let form = registrationController else { return }
        form.onCountryChange(country: country)
        apply(form.currentState)
    }

    /// Back from the form: nothing was stored; step 1 says the sign-up did not finish.
    func leaveRegistration() {
        guard let form = registrationController else { return }
        form.onBack()
        apply(form.currentState)
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
        // The field is capped at 50 characters, so every error is about the address itself.
        emailError = state.emailError?.signInMessage.map(L10n.message)
        isSubmitting = state.isSubmitting
        isJoiningAsGuest = state.isJoiningAsGuest
        if step == .email { notice = emailNotice }
    }

    private func apply(_ state: PhoneLoginState) {
        phoneText = state.formattedNumber
        country = state.country
        isPhoneSubmitting = state.isSubmitting
        // The prototype's message for India's ten-digit numbers; the UIKit app's for the others.
        phoneError = state.numberError?.message(isIndia: Self.isIndia(state.country), isRegistration: false).map(L10n.message)
    }

    private func apply(_ state: SocialLoginState) {
        socialInFlight = state.inFlight
        if state.succeeded {
            doneNotice = state.notice.map(Self.text)
            step = .done
        }
    }

    private func apply(_ state: OtpState) {
        codeText = state.code
        resendSeconds = Int(state.resendSecondsLeft)
        isVerifying = state.isVerifying
        isResending = state.isResending
        otpError = state.error.map(Self.text)
        codeInfo = state.info.map(Self.text)
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

    private func apply(_ state: RegistrationState) {
        registrationKind = state.kind
        registrationNameText = state.name
        registrationEmailText = state.email
        registrationCountry = state.country
        registrationNumberText = state.formattedNumber
        referralText = state.referralCode
        isReferralVisible = state.isReferralVisible
        isRegistering = state.isSubmitting
        registrationNameError = state.nameError?.message.map(L10n.message)
        registrationEmailError = state.emailError?.registrationMessage.map(L10n.message)
        registrationNumberError = state.numberError?.message(isIndia: Self.isIndia(state.country), isRegistration: true).map(L10n.message)
        notice = state.error.map(Self.text)
        if state.step == .success {
            registeredName = state.name.trimmingCharacters(in: .whitespaces)
            doneNotice = nil
            step = .done
        } else {
            step = .register
        }
    }

    private func handle(_ effect: EmailLoginEffect) {
        switch effect {
        case let sent as EmailLoginEffectCodeSent:
            startOtp(.email(sent.email, deviceLimit: nil))
        case let devicesEffect as EmailLoginEffectShowDevices:
            startOtp(.email(devicesEffect.email, deviceLimit: devicesEffect.limit))
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

    private func handle(_ effect: PhoneLoginEffect) {
        switch effect {
        case let requested as PhoneLoginEffectCodeRequested:
            startOtp(.phone(requested.phone, deviceLimit: nil))
        case let devicesEffect as PhoneLoginEffectShowDevices:
            startOtp(.phone(devicesEffect.phone, deviceLimit: devicesEffect.limit))
        case let message as PhoneLoginEffectShowMessage:
            emailNotice = Self.text(message.message)
            if step == .email { notice = emailNotice }
        default:
            break
        }
    }

    private func handle(_ effect: SocialLoginEffect) {
        switch effect {
        case let signedIn as SocialLoginEffectSignedIn:
            let credentials = AuthCredentials(signedIn.session)
            sessionTask = Task { [account] in await account.complete(with: credentials) }
        case is SocialLoginEffectAuthenticated:
            Task { [sessionTask] in
                await sessionTask?.value
                self.isFinished = true
            }
        case let devicesEffect as SocialLoginEffectShowDevices:
            startOtp(.socialDevices(devicesEffect.credential, limit: devicesEffect.limit))
        case let message as SocialLoginEffectShowMessage:
            emailNotice = Self.text(message.message)
            if step == .email { notice = emailNotice }
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
        case let needed as OtpEffectRegistrationNeeded:
            startRegistration(needed.registration)
        default:
            break
        }
    }

    private func handle(_ effect: RegistrationEffect) {
        switch effect {
        case let signedIn as RegistrationEffectSignedIn:
            let credentials = AuthCredentials(signedIn.session)
            sessionTask = Task { [account] in await account.complete(with: credentials) }
        case is RegistrationEffectAuthenticated:
            Task { [sessionTask] in
                await sessionTask?.value
                self.isFinished = true
            }
        case let cancelled as RegistrationEffectCancelled:
            endRegistration()
            endOtp()
            step = .email
            emailNotice = Self.text(cancelled.message)
            notice = emailNotice
        default:
            break
        }
    }

    /// The code step verified a new account: its sign-up form replaces the code step.
    private func startRegistration(_ registration: PendingRegistration) {
        endRegistration()
        let controller = graph.registrationController(registration: registration, config: config)
        registrationController = controller
        registrationWatchers.add(controller.close)
        registrationWatchers.add(controller.watchState { [weak self] state in
            MainActor.assumeIsolated { self?.apply(state) }
        }.close)
        registrationWatchers.add(controller.watchEffects { [weak self] effect in
            MainActor.assumeIsolated { self?.handle(effect) }
        }.close)
        // The code step is finished with; its watchers would otherwise keep driving `step`.
        otpWatchers.closeAll()
        otpController = nil
        notice = nil
        apply(controller.currentState)
    }

    private func endRegistration() {
        registrationWatchers.closeAll()
        registrationController = nil
        registrationKind = nil
        isRegistering = false
        isReferralVisible = false
        registrationNameError = nil
        registrationEmailError = nil
        registrationNumberError = nil
    }

    /// What the code step (or, for Google / Apple, the device step) starts from.
    private enum OtpStart {
        case email(String, deviceLimit: DeviceLimit?)
        case phone(PhoneNumber, deviceLimit: DeviceLimit?)
        case socialDevices(SocialCredential, limit: DeviceLimit)
    }

    private func startOtp(_ start: OtpStart) {
        endOtp()
        let controller: OtpController
        switch start {
        case let .email(email, deviceLimit):
            controller = graph.otpController(email: email, initialDeviceLimit: deviceLimit, config: config)
        case let .phone(phone, deviceLimit):
            controller = graph.phoneOtpController(phone: phone, sender: phoneSender, initialDeviceLimit: deviceLimit, config: config)
        case let .socialDevices(credential, limit):
            controller = graph.socialDevicesController(credential: credential, limit: limit, config: config)
        }
        sentTo = controller.currentState.email
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
        codeInfo = nil
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
            return L10n.string(.errorGeneric)
        }
        return text(for: key)
    }

    private static func isIndia(_ country: CountryDialCode) -> Bool {
        country.dialCode == CountryDialCodes.shared.INDIA.dialCode
    }

    /// The shared catalog's text for `key` (the same mapping AndroidJP uses).
    static func text(for key: AuthMessageKey) -> String {
        L10n.message(key.resource)
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
