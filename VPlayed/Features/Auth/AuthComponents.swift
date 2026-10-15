import SwiftUI
import Combine
import UIKit

/// "STEP 1 OF 3" above a Login step heading.
struct AuthStepLabel: View {
    let step: Int

    var body: some View {
        Text("Step \(step) of 3")
            .textCase(.uppercase)
            .font(Theme.Typography.stepLabel)
            .letterSpacing(1.3)
            .foregroundStyle(Theme.Palette.primary)
            .accessibilityHidden(true)
    }
}

/// A Login step heading, smaller on phones as in the prototype.
struct AuthTitle: View {
    let text: LocalizedStringKey
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Text(text)
            .font(sizeClass == .regular ? Theme.Typography.authTitleLarge : Theme.Typography.authTitle)
            .letterSpacing(-0.4)
            .foregroundStyle(Theme.Palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The prototype's text field: a faint fill, a hairline that turns red on error, 52pt tall.
struct AuthFieldBackground: ViewModifier {
    var isInvalid = false
    var isFocused = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control)
        content
            .font(Theme.Typography.fieldValue)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            // A faint fill on the dark card, white on the light one (as in the prototype's light theme).
            .background(colorScheme == .dark ? Theme.Palette.textPrimary.opacity(0.06) : Theme.Palette.surface, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: isInvalid || isFocused ? 1.5 : 1)
            }
    }

    private var borderColor: Color {
        if isInvalid { return Theme.Palette.primary }
        return isFocused ? Theme.Palette.textPrimary.opacity(0.45) : Theme.Palette.textPrimary.opacity(0.2)
    }
}

/// A full-width form button label (Continue, social sign-in, guest). Logos lead; the arrow on
/// Continue and Verify trails, as in the prototype. A spinner replaces the icon while loading.
struct AuthButtonLabel<Icon: View>: View {
    let title: LocalizedStringKey
    var font = Theme.Typography.formButton
    var iconTrails = false
    var isLoading = false
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 10) {
            if !iconTrails { leadingOrTrailing }
            Text(title)
            if iconTrails { leadingOrTrailing }
        }
        .font(font)
        .frame(maxWidth: .infinity, minHeight: 38)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingOrTrailing: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            icon()
        }
    }
}

extension View {
    /// Glass in the prototype's 8pt rounded rectangle, for the full-width form buttons.
    func authButtonShape() -> some View {
        buttonBorderShape(.roundedRectangle(radius: Theme.Radius.control))
    }
}

/// An error banner above the form: server messages, connection problems.
struct AuthNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.primary)
            Text(verbatim: message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.Palette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(Theme.Palette.primary.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Six boxes for the sign-in code, typed into one hidden field so paste and the keyboard's
/// one-time-code suggestion fill all six at once.
struct CodeField: View {
    @Binding var code: String
    var isFocused: FocusState<Bool>.Binding
    @State private var isKeyboardShown = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<SharedLoginViewModel.codeLength, id: \.self) { index in
                box(at: index)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background {
            TextField(String(), text: $code)
                .focused(isFocused)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel(Text("Verification code"))
                .accessibilityIdentifier("otp_code_field")
                .accessibilityValue(Text(verbatim: code))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: focus)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            isKeyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardShown = false
        }
        // Digits read left to right in every language.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func focus() {
        // When the keyboard goes away without the field asking (a tap elsewhere on iPad, the iPad
        // keyboard's hide key), the focus state can stay true, so setting it again does nothing and
        // the keyboard never returns. Drop focus first, then take it back on the next update.
        if isFocused.wrappedValue && !isKeyboardShown {
            isFocused.wrappedValue = false
            Task { isFocused.wrappedValue = true }
            return
        }
        isFocused.wrappedValue = true
    }

    private func box(at index: Int) -> some View {
        let digits = Array(code)
        let isCurrent = isFocused.wrappedValue && index == min(digits.count, SharedLoginViewModel.codeLength - 1)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control)
        return shape
            .fill(Theme.Palette.textPrimary.opacity(0.06))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 52)
            .overlay {
                shape.strokeBorder(
                    isCurrent ? Theme.Palette.primary : Theme.Palette.textPrimary.opacity(index < digits.count ? 0.35 : 0.14),
                    lineWidth: isCurrent ? 1.5 : 1
                )
            }
            .overlay {
                Text(verbatim: index < digits.count ? String(digits[index]) : "")
                    .font(Theme.Typography.codeDigit)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
    }
}
