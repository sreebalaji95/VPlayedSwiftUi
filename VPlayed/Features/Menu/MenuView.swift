import SwiftUI

/// The hamburger menu, shown in `MenuDrawer` from the Home toolbar: the account, browse
/// destinations, then app settings. Rows open their screen in the current tab, and the drawer
/// closes behind them.
struct MenuView: View {
    let onClose: () -> Void
    @Environment(\.openRoute) private var openRoute
    @Environment(LanguageStore.self) private var languageStore
    @Environment(AccountStore.self) private var account
    @State private var confirmsSignOut = false
    @State private var isSigningOut = false
    @State private var signOutError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                GlassGroup {
                    VStack(spacing: 10) {
                        accountRows
                            .padding(.bottom, 14)

                        Button { openRoute(.movies) } label: {
                            MenuRow(symbol: "film", title: "Movies") { EmptyView() }
                        }
                        .buttonStyle(GlassRowStyle.style)
                        .padding(.bottom, 14)

                        Button { openRoute(.language) } label: {
                            MenuRow(symbol: "globe", title: "Language") {
                                Text(verbatim: languageStore.language.nativeName)
                            }
                        }
                        .buttonStyle(GlassRowStyle.style)
                    }
                }
                .padding(Theme.Spacing.gutter)
            }
            // Only scrolls once rows overflow, so short menus leave horizontal swipes to the drawer.
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Menu"))
    }

    /// Guests see "Sign in" too: a guest session isn't an account (as in the UIKit app).
    @ViewBuilder
    private var accountRows: some View {
        if case .signedIn(let credentials) = account.state {
            VStack(alignment: .leading, spacing: 10) {
                if let name = credentials.displayName {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: 32, height: 32)
                        Text(verbatim: name)
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 14)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Signed in as \(name)"))
                }
                Button { confirmsSignOut = true } label: {
                    MenuRow(symbol: "rectangle.portrait.and.arrow.forward", title: "Sign out") {
                        if isSigningOut { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(GlassRowStyle.style)
                .disabled(isSigningOut)
                .confirmationDialog(Text("Sign out of \(Brand.name)?"), isPresented: $confirmsSignOut, titleVisibility: .visible) {
                    Button("Sign out", role: .destructive) { Task { await signOut() } }
                    Button("Cancel", role: .cancel) {}
                }
                if let signOutError {
                    Text(verbatim: signOutError)
                        .font(Theme.Typography.bodySmall)
                        .foregroundStyle(Theme.Palette.primary)
                        .padding(.horizontal, 14)
                }
            }
        } else {
            Button { openRoute(.signIn) } label: {
                MenuRow(symbol: "person.crop.circle", title: "Sign in") { EmptyView() }
            }
            .buttonStyle(GlassRowStyle.style)
        }
    }

    private func signOut() async {
        isSigningOut = true
        signOutError = nil
        defer { isSigningOut = false }
        do {
            try await account.signOut()
        } catch {
            signOutError = (error as? APIError)?.userMessage ?? APIError.network(code: 0).userMessage
        }
    }

    private var header: some View {
        HStack {
            BrandWordmark()
            Spacer(minLength: 8)
            Button(action: onClose) {
                Label("Close menu", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .glassButtonStyle()
            .buttonBorderShape(.circle)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// The glass row used by Menu and Language.
enum GlassRowStyle {
    static let style = GlassCardButtonStyle(shape: RoundedRectangle(cornerRadius: Theme.Radius.row), padding: 14)
}

/// Icon, title, trailing value and a forward chevron (mirrored in right-to-left languages).
private struct MenuRow<Value: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 32, height: 32)
            Text(title)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: 8)
            value()
                .font(Theme.Typography.rowValue)
                .foregroundStyle(Theme.Palette.textSecondary)
            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
