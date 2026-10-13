import SwiftUI

/// Sign in, from the prototype's "VPlayed Sign Up" page: email, then the 6-digit code, then
/// "You're all set", plus guest access when the server allows it. Presented over the app by
/// `RootView`; it closes itself once a session starts. The social buttons are for show only.
struct LoginView: View {
    @State private var model: LoginViewModel
    @Environment(AppStartup.self) private var startup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool

    init(account: AccountStore, service: any AuthServicing = AuthService()) {
        _model = State(initialValue: LoginViewModel(account: account, service: service))
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
        #if !os(visionOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .scrollBounceBehavior(.basedOnSize)
        .background { background }
        .overlay(alignment: .topTrailing) { closeButton }
        .tint(Theme.Palette.textPrimary)
        .animation(.snappy, value: model.step)
        .animation(.snappy, value: model.notice)
        .onChange(of: model.step) { _, step in
            emailFocused = step == .email
            codeFocused = step == .code
        }
        .onChange(of: model.isFinished) { _, finished in
            if finished { dismiss() }
        }
        .task(id: model.step) {
            // "You're all set" moves on by itself after 3 seconds, as in the prototype.
            guard model.step == .done else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { dismiss() }
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
                    socialButton("Sign up with Google") {
                        Image(.googleLogo)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    socialButton("Sign up with Apple") {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .padding(.bottom, 22)

            orDivider
                .padding(.bottom, 20)

            Text("Email ID")
                .font(Theme.Typography.fieldLabel)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.bottom, 8)
            TextField(String(), text: $model.email, prompt: Text(verbatim: "name@example.com").foregroundStyle(Theme.Palette.textTertiary))
                .focused($emailFocused)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                #if !os(macOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.continue)
                .onSubmit { Task { await model.continueWithEmail() } }
                .modifier(AuthFieldBackground(isInvalid: model.emailError != nil, isFocused: emailFocused))
                .accessibilityLabel(Text("Email ID"))
            Group {
                if let error = model.emailError {
                    Text(verbatim: error)
                        .font(Theme.Typography.fieldLabel)
                        .foregroundStyle(Theme.Palette.primary)
                } else {
                    Text("We'll send a 6-digit code to verify it's you.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.top, 7)

            Button { Task { await model.continueWithEmail() } } label: {
                AuthButtonLabel(title: "Continue", font: Theme.Typography.buttonLarge, iconTrails: true, isLoading: model.isSending) {
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .glassButtonStyle(.primary)
            .authButtonShape()
            .disabled(model.isSending)
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
                .disabled(model.isJoiningAsGuest)
                .padding(.top, 18)
            }
        }
    }

    /// Google and Apple sign-in are shown as designed but not connected yet, so they do nothing.
    private func socialButton(_ title: LocalizedStringKey, @ViewBuilder icon: @escaping () -> some View) -> some View {
        Button {} label: {
            AuthButtonLabel(title: title, icon: icon)
        }
        .glassButtonStyle()
        .authButtonShape()
        .disabled(true)
        .accessibilityHint(Text("Not available yet"))
    }

    private var orDivider: some View {
        HStack(spacing: 14) {
            Rectangle().fill(Theme.Palette.line).frame(height: 1)
            Text("or continue with email")
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
                .padding(.bottom, 22)

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
            AuthTitle(text: "You're all set")
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            Text("Your \(Brand.name) account is ready.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
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
