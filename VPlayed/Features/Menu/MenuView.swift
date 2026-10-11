import SwiftUI

/// The hamburger menu, shown in `MenuDrawer` from the Home toolbar: browse destinations, then
/// app settings. Rows open their screen in the current tab, and the drawer closes behind them.
struct MenuView: View {
    let onClose: () -> Void
    @Environment(\.openRoute) private var openRoute
    @Environment(LanguageStore.self) private var languageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                GlassGroup {
                    VStack(spacing: 10) {
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

    private var header: some View {
        HStack {
            // Same asset as the splash and the Home toolbar, so it has the light and dark variants.
            Image(.splashLogo)
                .resizable()
                .scaledToFit()
                .frame(height: Theme.Layout.headerLogoHeight)
                .accessibilityLabel("VPlayed")
                .accessibilityAddTraits(.isHeader)
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
    static let style = GlassCardButtonStyle(shape: RoundedRectangle(cornerRadius: 22), padding: 14)
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: 8)
            value()
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textSecondary)
            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
