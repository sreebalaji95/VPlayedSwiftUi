import SwiftUI
// Kotlin classes are not Sendable; they are only used on the main thread here.
@preconcurrency import Shared

/// Sign in, from the prototype's "VPlayed Sign Up" page: email (or a mobile number, when the
/// server asks for phone verification), then the 6-digit code, a new account's sign-up form
/// (prototype "Complete your profile"), then "You're all set", plus Google,
/// Apple and guest access when the server allows it. Presented over the app by `RootView`; it
/// closes itself once a session starts. The flow comes from `SharedLoginViewModel`, on the Kotlin
/// shared controllers.
struct LoginView: View {
    @State private var model: SharedLoginViewModel
    @Environment(AppStartup.self) private var startup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.locale) private var locale
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool
    @FocusState private var registrationField: RegistrationField?
    /// The sign-up form's mobile number (`PhoneField` takes a Bool focus binding).
    @FocusState private var phoneFocused: Bool

    private enum RegistrationField: Hashable { case name, email, referral }

    /// `verificationMethod` comes from the common settings; `notice` is shown above the form (an expired session).
    init(account: AccountStore, verificationMethod: CommonSettings.VerificationMethod? = nil, notice: String? = nil) {
        _model = State(initialValue: SharedLoginViewModel(account: account, verificationMethod: verificationMethod, initialNotice: notice))
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                card
                    .frame(maxWidth: 460)
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.top, 64)
                    .padding(.bottom, 32)
                    // Centred vertically when it fits, as in the prototype; scrolls when it doesn't.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background { background }
        .overlay(alignment: .topTrailing) { closeButton }
        .tint(Theme.Palette.textPrimary)
        .animation(.snappy, value: model.step)
        .animation(.snappy, value: model.notice)
        .onChange(of: model.step) { _, step in
            emailFocused = step == .email
            codeFocused = step == .code
            registrationField = step == .register ? .name : nil
        }
        // Guest sessions at once; sign-in after "You're all set" has shown for 3 seconds.
        .onChange(of: model.isFinished) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear { model.stopTimers() }
    }

    // MARK: Chrome

    private var background: some View {
        Theme.Palette.background
            .overlay {
                RadialGradient(
                    colors: [Theme.Palette.primary.opacity(colorScheme == .dark ? 0.22 : 0.12), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 360
                )
            }
            .ignoresSafeArea()
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Label("Close", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .glassButtonStyle()
        .buttonBorderShape(.circle)
        .keyboardShortcut(.cancelAction)
        .padding(.top, 12)
        .padding(.horizontal, Theme.Spacing.gutter)
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.popover)
        let isCompact = sizeClass != .regular
        return Group {
            switch model.step {
            case .email: emailStep
            case .code: codeStep
            case .devices: devicesStep
            case .register: registerStep
            case .done: doneStep
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .padding(.horizontal, isCompact ? 20 : 32)
        .padding(.vertical, isCompact ? 30 : 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface.opacity(colorScheme == .dark ? 0.92 : 1), in: shape)
        .overlay { shape.strokeBorder(Theme.Palette.line, lineWidth: 1) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.08), radius: 24, y: 16)
    }

    // MARK: Step 1 — email

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthStepLabel(step: 1)
                .padding(.bottom, 12)
            AuthTitle(text: "Sign in or create your account")
                .padding(.bottom, 22)

            if let notice = model.notice {
                AuthNotice(message: notice)
                    .padding(.bottom, 18)
            }

            GlassGroup(spacing: 10) {
                VStack(spacing: 10) {
                    if model.isGoogleAvailable {
                        socialButton("Sign up with Google", provider: .google) {
                            Image(.googleLogo)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                    }
                    socialButton("Sign up with Apple", provider: .apple) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .padding(.bottom, 22)

            orDivider
                .padding(.bottom, 20)

            if model.usesPhone {
                phoneField
            } else {
                emailField
            }

            Button { Task { await submit() } } label: {
                AuthButtonLabel(title: "Continue", font: Theme.Typography.buttonLarge, iconTrails: true, isLoading: model.isSending) {
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .glassButtonStyle(.primary)
            .authButtonShape()
            .disabled(model.isBusy)
            .padding(.top, 20)

            termsLine
                .padding(.top, 14)

            if startup.settings?.isGuestUser == true {
                Button { Task { await model.continueAsGuest() } } label: {
                    AuthButtonLabel(title: "Continue as guest", isLoading: model.isJoiningAsGuest) {
                        Image(systemName: "person")
                            .font(.system(size: 17, weight: .medium))
                    }
                }
                .glassButtonStyle()
                .authButtonShape()
                .disabled(model.isBusy)
                .padding(.top, 18)
            }
        }
    }

    private func submit() async {
        if model.usesPhone {
            await model.continueWithPhone()
        } else {
            await model.continueWithEmail()
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Email ID")
                .font(Theme.Typography.fieldLabel)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.bottom, 8)
            TextField(String(), text: $model.email, prompt: Text(verbatim: "name@example.com").foregroundStyle(Theme.Palette.textTertiary))
                .focused($emailFocused)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .submitLabel(.continue)
                .onSubmit { Task { await model.continueWithEmail() } }
                .modifier(AuthFieldBackground(isInvalid: model.emailError != nil, isFocused: emailFocused))
                .accessibilityLabel(Text("Email ID"))
                .accessibilityIdentifier("login_email_field")
            fieldFootnote(error: model.emailError, help: "We'll send a 6-digit code to verify it's you.")
        }
    }

    /// The prototype's mobile-number field (`vp-login-method.js`): country chip, then the number.
    private var phoneField: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mobile number")
                .font(Theme.Typography.fieldLabel)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.bottom, 8)
            PhoneField(
                number: $model.phoneNumber,
                country: model.country,
                countries: model.countries,
                isInvalid: model.phoneError != nil,
                isFocused: $emailFocused,
                countryName: { locale.localizedString(forRegionCode: $0.regionCode) ?? $0.name },
                onSelectCountry: model.selectCountry
            )
            .onChange(of: emailFocused) { _, focused in
                if !focused { model.phoneFieldLostFocus() }
            }
            fieldFootnote(error: model.phoneError, help: "We'll text a 6-digit code to verify it's you.")
        }
    }

    /// The field's error, else its help line.
    private func fieldFootnote(error: String?, help: LocalizedStringKey) -> some View {
        Group {
            if let error {
                Text(verbatim: error)
                    .font(Theme.Typography.fieldLabel)
                    .foregroundStyle(Theme.Palette.primary)
            } else {
                Text(help)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.top, 7)
    }

    /// Google and Apple sign-in (shared `SocialLoginController`); a spinner while its sheet or call runs.
    private func socialButton(_ title: LocalizedStringKey, provider: SocialProvider, @ViewBuilder icon: @escaping () -> some View) -> some View {
        Button {
            Task {
                if provider == .google {
                    await model.signInWithGoogle()
                } else {
                    await model.signInWithApple()
                }
            }
        } label: {
            AuthButtonLabel(title: title, isLoading: model.socialInFlight == provider, icon: icon)
        }
        .glassButtonStyle()
        .authButtonShape()
        .disabled(model.isBusy)
    }

    private var orDivider: some View {
        HStack(spacing: 14) {
            Rectangle().fill(Theme.Palette.line).frame(height: 1)
            Text(model.usesPhone ? "or continue with mobile number" : "or continue with email")
                .font(Theme.Typography.caption)
                .letterSpacing(0.6)
                .foregroundStyle(Theme.Palette.textTertiary)
                .layoutPriority(1)
            Rectangle().fill(Theme.Palette.line).frame(height: 1)
        }
    }

    private var termsLine: some View {
        var text = AttributedString(localized: "I am above 18 years of age and by proceeding I agree to the [Terms of use](terms) and [privacy policy](privacy).", bundle: .localized)
        for run in text.runs where run.link != nil {
            text[run.range].foregroundColor = Theme.Palette.primary
            text[run.range].font = Theme.Typography.fieldLabel
        }
        return Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                // The same pages the UIKit app opens (`openTermsOfUse`, `openPrivacyPolicy`).
                let web = APIEnvironment.current.webBaseURL
                switch url.absoluteString {
                case "terms": openURL(web.appending(path: "terms-and-conditions"))
                case "privacy": openURL(web.appending(path: "privacy-policy/mobile"))
                default: break
                }
                return .handled
            })
    }

    // MARK: Step 2 — code

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.editEmail() } label: {
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(SpacedLabelStyle(spacing: 6))
                    .font(Theme.Typography.note)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 18)

            AuthStepLabel(step: 2)
                .padding(.bottom, 12)
            AuthTitle(text: "Verify it's you")
                .padding(.bottom, 10)

            codeNote
                .padding(.bottom, model.codeInfo == nil ? 22 : 10)

            if let info = model.codeInfo {
                Text(verbatim: info)
                    .font(Theme.Typography.bodySmall)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
            }

            if let notice = model.notice {
                AuthNotice(message: notice)
                    .padding(.bottom, 18)
            }

            CodeField(code: $model.code, isFocused: $codeFocused)
                .padding(.bottom, 22)

            resendRow
                .padding(.bottom, 22)

            Button { Task { await model.verify() } } label: {
                AuthButtonLabel(title: "Verify & continue", font: Theme.Typography.buttonLarge, iconTrails: true, isLoading: model.isVerifying) {
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .glassButtonStyle(.primary)
            .authButtonShape()
            .disabled(!model.canVerify)
        }
        .onAppear { codeFocused = true }
    }

    private var codeNote: some View {
        // Built from plain strings, not Markdown, so characters in the address are never read as formatting.
        let address = model.sentTo
        var text = AttributedString(String(localized: "Enter the 6-digit code we sent to \(address)", bundle: .localized))
        if !address.isEmpty, let range = text.range(of: address) {
            text[range].foregroundColor = Theme.Palette.textPrimary
            text[range].font = Theme.Typography.note
        }
        var change = AttributedString(String(localized: "Change", bundle: .localized))
        change.link = URL(string: "change")
        change.foregroundColor = Theme.Palette.primary
        change.font = Theme.Typography.note
        text += AttributedString(" ") + change
        return Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { _ in
                model.editEmail()
                return .handled
            })
    }

    private var resendRow: some View {
        HStack(spacing: 4) {
            Text("Didn't get the code?")
                .foregroundStyle(Theme.Palette.textSecondary)
            if model.resendSeconds > 0 {
                Text("Resend in \(Duration.seconds(model.resendSeconds).formatted(.time(pattern: .minuteSecond)))")
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .monospacedDigit()
            } else {
                Button { Task { await model.resend() } } label: {
                    Text("Resend")
                        .font(Theme.Typography.note)
                        .foregroundStyle(Theme.Palette.primary)
                }
                .buttonStyle(.plain)
                .disabled(model.isSending)
            }
        }
        .font(Theme.Typography.bodySmall)
    }

    // MARK: Device limit (off until the backend confirms it is safe, see `AuthFeatures`)

    private var devicesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.editEmail() } label: {
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(SpacedLabelStyle(spacing: 6))
                    .font(Theme.Typography.note)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isSigningOut)
            .padding(.bottom, 18)

            AuthTitle(text: "Maximum devices reached")
                .padding(.bottom, 10)
            Text("Your account is signed in on as many devices as it allows. Sign out from one of them to continue.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            if let notice = model.notice {
                AuthNotice(message: notice)
                    .padding(.bottom, 18)
            }

            VStack(spacing: 10) {
                ForEach(model.devices) { device in
                    deviceRow(device)
                }
            }
            .padding(.bottom, 22)

            if model.hasSignedOutDevice {
                Button { model.continueAfterSignOut() } label: {
                    AuthButtonLabel(title: "Continue", font: Theme.Typography.buttonLarge, iconTrails: true, isLoading: model.isSigningOut) {
                        Image(systemName: "arrow.forward")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .glassButtonStyle(.primary)
                .authButtonShape()
                .disabled(model.isSigningOut)
            } else if !model.devices.isEmpty {
                Button { model.signOutAllDevices() } label: {
                    AuthButtonLabel(title: "Sign out from all devices", isLoading: model.isSigningOut) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .glassButtonStyle()
                .authButtonShape()
                .disabled(model.isSigningOut)
            }
        }
    }

    private func deviceRow(_ device: LoginDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(for: device.kind))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: device.name)
                    .font(Theme.Typography.note)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if device.isCurrent {
                    Text("This device")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.primary)
                } else if let detail = device.detail {
                    Text(verbatim: detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Button("Sign out") { model.signOut(device) }
                .font(Theme.Typography.note)
                .foregroundStyle(Theme.Palette.primary)
                .buttonStyle(.plain)
                .disabled(model.isSigningOut)
        }
        .padding(.vertical, 10)
        .modifier(AuthFieldBackground())
        .accessibilityElement(children: .combine)
    }

    private static func symbol(for kind: LoginDevice.Kind) -> String {
        switch kind {
        case .desktop: "desktopcomputer"
        case .phone: "iphone"
        case .tv: "tv"
        case .other: "questionmark.square.dashed"
        }
    }

    // MARK: Sign-up form (new accounts)

    /// UIKit `RegisterViewController`, styled as the prototype's "Complete your profile": the name,
    /// then the mobile number (email accounts) or the email (phone accounts); what the account signed
    /// in with is shown read-only.
    private var registerStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.leaveRegistration() } label: {
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(SpacedLabelStyle(spacing: 6))
                    .font(Theme.Typography.note)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isRegistering)
            .padding(.bottom, 18)

            AuthStepLabel(step: 3)
                .padding(.bottom, 12)
            AuthTitle(text: "Tell us about you")
                .padding(.bottom, 10)
            Text("Complete your profile to finish creating your \(Brand.name) account.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            if let notice = model.notice {
                AuthNotice(message: notice)
                    .padding(.bottom, 18)
            }

            VStack(alignment: .leading, spacing: 18) {
                registrationNameField
                if model.registrationKind == .emailAccount {
                    registrationPhoneField
                    readOnlyField(title: "Email ID", value: model.registrationEmail)
                } else {
                    registrationEmailField
                    readOnlyField(title: "Mobile number", value: "\(model.registrationCountry.prefix) \(model.registrationNumber)")
                }
                if model.registrationKind == .emailAccount {
                    referralSection
                }
            }

            Button { model.submitRegistration() } label: {
                AuthButtonLabel(title: "Finish setup", font: Theme.Typography.buttonLarge, iconTrails: true, isLoading: model.isRegistering) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .glassButtonStyle(.primary)
            .authButtonShape()
            .disabled(model.isRegistering)
            .padding(.top, 24)
        }
    }

    private var registrationNameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldTitle("Full name")
            TextField(String(), text: $model.registrationName, prompt: Text("Enter your name").foregroundStyle(Theme.Palette.textTertiary))
                .focused($registrationField, equals: .name)
                .textContentType(.name)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .onSubmit {
                    if model.registrationKind == .emailAccount {
                        phoneFocused = true
                    } else {
                        registrationField = .email
                    }
                }
                .modifier(AuthFieldBackground(isInvalid: model.registrationNameError != nil, isFocused: registrationField == .name))
                .accessibilityLabel(Text("Full name"))
                .accessibilityIdentifier("register_name_field")
            registrationError(model.registrationNameError)
        }
    }

    private var registrationEmailField: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldTitle("Email ID")
            TextField(String(), text: $model.registrationEmail, prompt: Text(verbatim: "name@example.com").foregroundStyle(Theme.Palette.textTertiary))
                .focused($registrationField, equals: .email)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { model.submitRegistration() }
                .modifier(AuthFieldBackground(isInvalid: model.registrationEmailError != nil, isFocused: registrationField == .email))
                .accessibilityLabel(Text("Email ID"))
                .accessibilityIdentifier("register_email_field")
            registrationError(model.registrationEmailError)
        }
    }

    private var registrationPhoneField: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldTitle("Mobile number")
            PhoneField(
                number: $model.registrationNumber,
                country: model.registrationCountry,
                countries: model.countries,
                isInvalid: model.registrationNumberError != nil,
                isFocused: $phoneFocused,
                countryName: { locale.localizedString(forRegionCode: $0.regionCode) ?? $0.name },
                onSelectCountry: model.selectRegistrationCountry
            )
            .accessibilityIdentifier("register_phone_field")
            registrationError(model.registrationNumberError)
        }
    }

    /// "Have a referral code?" opens the referral field (email accounts; `auth/update-profile` takes it).
    @ViewBuilder private var referralSection: some View {
        if model.isReferralVisible {
            VStack(alignment: .leading, spacing: 0) {
                fieldTitle("Referral code")
                TextField(String(), text: $model.referralCode, prompt: Text("Enter referral code").foregroundStyle(Theme.Palette.textTertiary))
                    .focused($registrationField, equals: .referral)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .modifier(AuthFieldBackground(isFocused: registrationField == .referral))
                    .accessibilityLabel(Text("Referral code"))
                    .accessibilityIdentifier("register_referral_field")
            }
        } else {
            Button {
                model.showReferral()
                registrationField = .referral
            } label: {
                Text("Have a referral code?")
                    .font(Theme.Typography.note)
                    .foregroundStyle(Theme.Palette.primary)
            }
            .buttonStyle(.plain)
            .disabled(model.isRegistering)
        }
    }

    /// What the account signed in with: shown, not editable (UIKit greys these fields out).
    private func readOnlyField(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldTitle(title)
            Text(verbatim: value)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(AuthFieldBackground())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(verbatim: value))
        }
    }

    private func fieldTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.Typography.fieldLabel)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.bottom, 8)
    }

    @ViewBuilder private func registrationError(_ error: String?) -> some View {
        if let error {
            Text(verbatim: error)
                .font(Theme.Typography.fieldLabel)
                .foregroundStyle(Theme.Palette.primary)
                .padding(.top, 7)
        }
    }

    // MARK: Step 3 — done

    private var doneStep: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.green)
                .frame(width: 84, height: 84)
                .background(Color.green.opacity(0.16), in: Circle())
                .padding(.bottom, 24)
                .accessibilityHidden(true)
            AuthStepLabel(step: 3)
                .padding(.bottom, 12)
            Group {
                if let name = model.registeredName, !name.isEmpty {
                    AuthTitle(text: "You're all set, \(name)")
                } else {
                    AuthTitle(text: "You're all set")
                }
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 10)
            Text("Your \(Brand.name) account is ready.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let doneNotice = model.doneNotice {
                Text(verbatim: doneNotice)
                    .font(Theme.Typography.bodySmall)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            AutoAdvanceBar()
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Taking you in…" with a bar that fills over the 3 seconds before the screen closes.
private struct AutoAdvanceBar: View {
    @State private var progress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Theme.Palette.textPrimary.opacity(0.14))
                .frame(width: 160, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Palette.primary)
                        .frame(width: 160 * progress, height: 3)
                }
                .flipsForRightToLeftLayoutDirection(true)
            Text("Taking you in…")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .onAppear {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.linear(duration: 3)) { progress = 1 }
            }
        }
    }
}
